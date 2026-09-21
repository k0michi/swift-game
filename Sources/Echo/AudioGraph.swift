@MainActor
final class AudioGraph {
    private struct Connection {
        let source: AudioNode
        let destination: AudioNode
        let output: UInt32
        let input: UInt32
    }

    private struct ParamConnection {
        let source: AudioNode
        let destination: AudioParam
        let output: UInt32
    }

    @MainActor
    private final class RenderSlot {
        let node: AudioNode
        var inputChannelCount: Int?
        var outputChannelCount: Int
        var sources: [RenderSlot] = []
        var paramSources: [(AudioParam, [RenderSlot])] = []
        var isMuted = false
        var isCycleBreaker = false

        init(node: AudioNode) {
            self.node = node
            inputChannelCount = node.numberOfInputs == 0 ? nil
                : node is AudioDestinationNode ? Int(node.channelCount) : 1
            outputChannelCount = node is AudioDestinationNode ? Int(node.channelCount) : 1
        }
    }

    private var connections: [Connection] = []
    private var paramConnections: [ParamConnection] = []
    private var orderedSlots: [RenderSlot] = []
    private var needsPreparation = true

    func invalidate() { needsPreparation = true }

    func connect(_ source: AudioNode, to destination: AudioNode, output: UInt32, input: UInt32) throws {
        if connections.contains(where: {
            $0.source === source && $0.destination === destination && $0.output == output && $0.input == input
        }) { return }
        connections.append(Connection(source: source, destination: destination, output: output, input: input))
        needsPreparation = true
    }

    func connect(_ source: AudioNode, to destination: AudioParam, output: UInt32) {
        guard !paramConnections.contains(where: {
            $0.source === source && $0.destination === destination && $0.output == output
        }) else { return }
        paramConnections.append(ParamConnection(source: source, destination: destination, output: output))
        needsPreparation = true
    }

    func disconnect(_ source: AudioNode) {
        connections.removeAll { $0.source === source }
        paramConnections.removeAll { $0.source === source }
        needsPreparation = true
    }

    func disconnect(_ source: AudioNode, output: UInt32) {
        connections.removeAll { $0.source === source && $0.output == output }
        paramConnections.removeAll { $0.source === source && $0.output == output }
        needsPreparation = true
    }

    @discardableResult
    func disconnect(_ source: AudioNode, from destination: AudioNode) -> Bool {
        let originalCount = connections.count
        connections.removeAll { $0.source === source && $0.destination === destination }
        needsPreparation = true
        return connections.count != originalCount
    }

    @discardableResult
    func disconnect(_ source: AudioNode, from destination: AudioParam) -> Bool {
        let originalCount = paramConnections.count
        paramConnections.removeAll { $0.source === source && $0.destination === destination }
        needsPreparation = true
        return paramConnections.count != originalCount
    }

    private func prepare(destination: AudioDestinationNode) {
        guard needsPreparation else { return }
        var slots: [ObjectIdentifier: RenderSlot] = [:]
        var order: [RenderSlot] = []

        func visit(_ node: AudioNode) -> RenderSlot {
            let identifier = ObjectIdentifier(node)
            if let slot = slots[identifier] { return slot }
            let slot = RenderSlot(node: node)
            slots[identifier] = slot
            for connection in connections where connection.destination === node {
                slot.sources.append(visit(connection.source))
            }
            for param in node.audioParams {
                let sources = paramConnections.filter { $0.destination === param }.map { visit($0.source) }
                if !sources.isEmpty {
                    slot.paramSources.append((param, sources))
                }
            }
            order.append(slot)
            return slot
        }

        let destinationSlot = visit(destination)
        let noCycleBreakers: Set<ObjectIdentifier> = []
        let cycleBreakers = Set(order.compactMap { slot -> ObjectIdentifier? in
            guard slot.node is DelayNode,
                  outgoingNodes(from: slot.node, ignoringInputsOf: noCycleBreakers).contains(where: { next in
                      next === slot.node || hasPath(
                          from: next, to: slot.node, ignoringInputsOf: noCycleBreakers
                      )
                  })
            else { return nil }
            return ObjectIdentifier(slot.node)
        })

        var ordered: [RenderSlot] = []
        var marked: Set<ObjectIdentifier> = []
        func orderVisit(_ slot: RenderSlot) {
            guard marked.insert(ObjectIdentifier(slot.node)).inserted else { return }
            if !cycleBreakers.contains(ObjectIdentifier(slot.node)) {
                slot.sources.forEach(orderVisit)
            }
            for (_, sources) in slot.paramSources {
                sources.forEach(orderVisit)
            }
            ordered.append(slot)
        }
        orderVisit(destinationSlot)
        for slot in order where cycleBreakers.contains(ObjectIdentifier(slot.node)) {
            slot.sources.forEach(orderVisit)
        }

        for slot in ordered {
            slot.isMuted = outgoingNodes(from: slot.node, ignoringInputsOf: cycleBreakers).contains { next in
                next === slot.node || hasPath(
                    from: next,
                    to: slot.node,
                    ignoringInputsOf: cycleBreakers
                )
            }
            slot.isCycleBreaker = cycleBreakers.contains(ObjectIdentifier(slot.node)) && !slot.isMuted
        }
        orderedSlots = ordered
        needsPreparation = false
    }

    func makeRenderPlan(destination: AudioDestinationNode, frameCount: Int) throws -> AudioRenderPlan {
        prepare(destination: destination)
        let indices = Dictionary(uniqueKeysWithValues: orderedSlots.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })

        let configurations = try orderedSlots.map { slot throws -> AudioRenderPlan.NodeConfiguration in
            let processor: AudioRenderPlan.Processor
            if let source = slot.node as? ConstantSourceNode {
                let offset = source.offset
                let paramSources = slot.paramSources.first { $0.0 === offset }?.1 ?? []
                processor = .constant(
                    startFrame: source.scheduledStartFrame,
                    stopFrame: source.scheduledStopFrame,
                    parameter: offset.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let delay = slot.node as? DelayNode {
                let delayTime = delay.delayTime
                let paramSources = slot.paramSources.first { $0.0 === delayTime }?.1 ?? []
                processor = .delay(
                    state: delay.renderState,
                    parameter: delayTime.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if slot.node is AudioDestinationNode {
                processor = .passThrough
            } else {
                throw WebAudioError.notSupported
            }

            return AudioRenderPlan.NodeConfiguration(
                inputChannelCount: slot.inputChannelCount,
                outputChannelCount: slot.outputChannelCount,
                interpretation: slot.node.channelInterpretation,
                channelCount: Int(slot.node.channelCount),
                channelCountMode: slot.node.channelCountMode,
                sources: slot.sources.map { indices[ObjectIdentifier($0)]! },
                isMuted: slot.isMuted,
                isCycleBreaker: slot.isCycleBreaker,
                processor: processor
            )
        }
        return AudioRenderPlan(
            configurations: configurations,
            frameCount: frameCount,
            destinationIndex: orderedSlots.firstIndex { $0.node === destination }!
        )
    }

    private func hasPath(
        from start: AudioNode,
        to target: AudioNode,
        ignoringInputsOf cycleBreakers: Set<ObjectIdentifier>
    ) -> Bool {
        var visited: Set<ObjectIdentifier> = []
        var pending = [start]
        while let node = pending.popLast() {
            if node === target { return true }
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: outgoingNodes(from: node, ignoringInputsOf: cycleBreakers))
        }
        return false
    }

    private func outgoingNodes(
        from node: AudioNode,
        ignoringInputsOf cycleBreakers: Set<ObjectIdentifier>
    ) -> [AudioNode] {
        connections.filter {
            $0.source === node && !cycleBreakers.contains(ObjectIdentifier($0.destination))
        }.map(\.destination)
            + paramConnections.compactMap { $0.source === node ? $0.destination.owner : nil }
    }

}
