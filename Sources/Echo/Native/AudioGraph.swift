// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// The connections between a context's nodes. They keep neither end: the
// context keeps what sounds or may sound, the caller keeps what it uses, and
// a connection whose end has gone goes too.
@MainActor
final class AudioGraph {
    private struct Connection {
        // A connection from or to the destination is from or to the
        // context's output, which outlives any one destination node.
        weak var source: AudioNode?
        let fromOutput: Bool
        weak var destination: AudioNode?
        let toOutput: Bool
        let output: UInt32
        let input: UInt32

        init(source: AudioNode, destination: AudioNode, output: UInt32, input: UInt32) {
            fromOutput = source is AudioDestinationNode
            toOutput = destination is AudioDestinationNode
            self.source = fromOutput ? nil : source
            self.destination = toOutput ? nil : destination
            self.output = output
            self.input = input
        }

        var isLive: Bool { (fromOutput || source != nil) && (toOutput || destination != nil) }

        func comes(from node: AudioNode) -> Bool {
            node is AudioDestinationNode ? fromOutput : source === node
        }

        func leads(to node: AudioNode) -> Bool {
            node is AudioDestinationNode ? toOutput : destination === node
        }
    }

    private struct ParamConnection {
        weak var source: AudioNode?
        let fromOutput: Bool
        weak var destination: AudioParam?
        // The parameter's node.
        weak var owner: AudioNode?
        let output: UInt32

        @MainActor
        init(source: AudioNode, destination: AudioParam, output: UInt32) {
            fromOutput = source is AudioDestinationNode
            self.source = fromOutput ? nil : source
            self.destination = destination
            owner = destination.owner
            self.output = output
        }

        var isLive: Bool { (fromOutput || source != nil) && destination != nil && owner != nil }

        func comes(from node: AudioNode) -> Bool {
            node is AudioDestinationNode ? fromOutput : source === node
        }
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
            outputChannelCount = (node as? AudioDestinationNode).map { Int($0.maxChannelCount) }
                ?? (node as? MediaStreamAudioSourceNode).map { Int($0.renderState.track.channelCount) }
                ?? (node is StereoPannerNode ? 2 : 1)
        }
    }

    private var connections: [Connection] = []
    private var paramConnections: [ParamConnection] = []
    // The destination node a plan is being made for, which stands for the
    // context's output.
    private weak var output: AudioDestinationNode?

    var connectionCount: Int { connections.count + paramConnections.count }

    func connect(_ source: AudioNode, to destination: AudioNode, output: UInt32, input: UInt32) throws {
        if connections.contains(where: {
            $0.comes(from: source) && $0.leads(to: destination) && $0.output == output && $0.input == input
        }) { return }
        connections.append(Connection(source: source, destination: destination, output: output, input: input))
    }

    func connect(_ source: AudioNode, to destination: AudioParam, output: UInt32) {
        guard !paramConnections.contains(where: {
            $0.comes(from: source) && $0.destination === destination && $0.output == output
        }) else { return }
        paramConnections.append(ParamConnection(source: source, destination: destination, output: output))
    }

    func disconnect(_ source: AudioNode) {
        connections.removeAll { $0.comes(from: source) }
        paramConnections.removeAll { $0.comes(from: source) }
    }

    func disconnect(_ source: AudioNode, output: UInt32) {
        connections.removeAll { $0.comes(from: source) && $0.output == output }
        paramConnections.removeAll { $0.comes(from: source) && $0.output == output }
    }

    @discardableResult
    func disconnect(_ source: AudioNode, from destination: AudioNode) -> Bool {
        let originalCount = connections.count
        connections.removeAll { $0.comes(from: source) && $0.leads(to: destination) }
        return connections.count != originalCount
    }

    @discardableResult
    func disconnect(_ source: AudioNode, from destination: AudioParam) -> Bool {
        let originalCount = paramConnections.count
        paramConnections.removeAll { $0.comes(from: source) && $0.destination === destination }
        return paramConnections.count != originalCount
    }

    // Removes the connections one of whose ends has gone. Returns whether
    // any went.
    func removeDeadConnections() -> Bool {
        let count = connectionCount
        connections.removeAll { !$0.isLive }
        paramConnections.removeAll { !$0.isLive }
        return connectionCount != count
    }

    // The nodes that `roots` lead to, through connections to nodes and to
    // parameters, without the roots unless one leads to another. The
    // context's output is not one.
    func nodes(downstreamOf roots: [AudioNode]) -> [AudioNode] {
        var reached: [ObjectIdentifier: AudioNode] = [:]
        var pending = roots
        while let node = pending.popLast() {
            let next = connections.compactMap { $0.comes(from: node) ? $0.destination : nil }
                + paramConnections.compactMap { $0.comes(from: node) ? $0.owner : nil }
            for node in next where reached.updateValue(node, forKey: ObjectIdentifier(node)) == nil {
                pending.append(node)
            }
        }
        return Array(reached.values)
    }

    // The nodes that render, sources first, each with what it is connected
    // from. Made again for each plan, as keeping them would keep the nodes;
    // the caller clears what each is connected from once done, as a cycle
    // would otherwise keep them anyway.
    private func prepare(destination: AudioDestinationNode) -> [RenderSlot] {
        output = destination
        defer { output = nil }
        var slots: [ObjectIdentifier: RenderSlot] = [:]
        var order: [RenderSlot] = []

        func visit(_ node: AudioNode) -> RenderSlot {
            let identifier = ObjectIdentifier(node)
            if let slot = slots[identifier] { return slot }
            let slot = RenderSlot(node: node)
            slots[identifier] = slot
            for connection in connections where connection.leads(to: node) {
                if let source = connection.fromOutput ? output : connection.source {
                    slot.sources.append(visit(source))
                }
            }
            for param in node.audioParams {
                let sources = paramConnections.filter { $0.destination === param }
                    .compactMap { $0.fromOutput ? output : $0.source }.map(visit)
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
        return ordered
    }

    func makeRenderPlan(destination: AudioDestinationNode, frameCount: Int) throws -> AudioRenderPlan {
        let orderedSlots = prepare(destination: destination)
        defer {
            for slot in orderedSlots {
                slot.sources = []
                slot.paramSources = []
            }
        }
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
                    ended: source.endedSignal,
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
            } else if let node = slot.node as? GainNode {
                let gain = node.gain
                let paramSources = slot.paramSources.first { $0.0 === gain }?.1 ?? []
                processor = .gain(
                    parameter: gain.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let filter = slot.node as? BiquadFilterNode {
                let parameters = [filter.frequency, filter.detune, filter.Q, filter.gain]
                processor = .biquad(
                    state: filter.renderState,
                    type: filter.type,
                    sampleRate: filter.context.sampleRate,
                    parameters: parameters.map(\.renderTimeline),
                    paramSources: parameters.map { param in
                        (slot.paramSources.first { $0.0 === param }?.1 ?? []).map { indices[ObjectIdentifier($0)]! }
                    }
                )
            } else if let source = slot.node as? AudioBufferSourceNode {
                processor = .bufferSource(
                    state: source.renderState,
                    ended: source.endedSignal,
                    sampleRate: source.context.sampleRate,
                    schedule: BufferSourceRenderState.Schedule(
                        content: source.content,
                        start: source.startTime,
                        stop: source.stopTime,
                        offset: source.offset,
                        duration: source.duration,
                        loop: source.loop,
                        loopStart: source.loopStart,
                        loopEnd: source.loopEnd
                    ),
                    playbackRate: source.playbackRate.renderTimeline,
                    detune: source.detune.renderTimeline,
                    paramSources: [source.playbackRate, source.detune].map { param in
                        (slot.paramSources.first { $0.0 === param }?.1 ?? []).map { indices[ObjectIdentifier($0)]! }
                    }
                )
            } else if let oscillator = slot.node as? OscillatorNode {
                let sources = [oscillator.frequency, oscillator.detune].map { param in
                    (slot.paramSources.first { $0.0 === param }?.1 ?? []).map { indices[ObjectIdentifier($0)]! }
                }
                processor = .oscillator(
                    state: oscillator.renderState,
                    ended: oscillator.endedSignal,
                    wave: oscillator.waveTable,
                    sampleRate: oscillator.context.sampleRate,
                    startTime: oscillator.startTime,
                    stopTime: oscillator.stopTime,
                    frequency: oscillator.frequency.renderTimeline,
                    detune: oscillator.detune.renderTimeline,
                    paramSources: sources
                )
            } else if let panner = slot.node as? StereoPannerNode {
                let pan = panner.pan
                let paramSources = slot.paramSources.first { $0.0 === pan }?.1 ?? []
                processor = .stereoPanner(
                    parameter: pan.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let shaper = slot.node as? WaveShaperNode {
                processor = .waveShaper(state: shaper.renderState, curve: shaper.curve, oversample: shaper.oversample)
            } else if let source = slot.node as? MediaStreamAudioSourceNode {
                processor = .mediaStream(state: source.renderState)
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
                sounding: slot.node.soundingSignal,
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
        connections.compactMap { connection -> AudioNode? in
            guard connection.comes(from: node),
                  let destination = connection.toOutput ? output : connection.destination,
                  !cycleBreakers.contains(ObjectIdentifier(destination))
            else { return nil }
            return destination
        }
            + paramConnections.compactMap { $0.comes(from: node) ? $0.owner : nil }
    }

}
#endif
