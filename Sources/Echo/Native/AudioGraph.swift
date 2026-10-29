// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// The connections between a context's node handlers, which keep both ends.
// Handlers refer to no other handler, so nothing here makes a reference
// cycle; the context removes what can no longer sound.
@MainActor
final class AudioGraph {
    private struct Connection {
        let source: AudioHandler
        let destination: AudioHandler
        let output: UInt32
        let input: UInt32
    }

    private struct ParamConnection {
        let source: AudioHandler
        let destination: AudioParamHandler
        let output: UInt32
    }

    @MainActor
    private final class RenderSlot {
        let node: AudioHandler
        var inputChannelCount: Int?
        var outputChannelCount: Int
        var sources: [RenderSlot] = []
        var paramSources: [(AudioParamHandler, [RenderSlot])] = []
        var isMuted = false
        var isCycleBreaker = false

        init(node: AudioHandler) {
            self.node = node
            inputChannelCount = node.numberOfInputs == 0 ? nil
                : node is AudioDestinationHandler ? Int(node.channelCount) : 1
            outputChannelCount = (node as? AudioDestinationHandler).map { Int($0.maxChannelCount) }
                ?? (node as? MediaStreamAudioSourceHandler).map { Int($0.renderState.track.channelCount) }
                ?? (node is StereoPannerHandler ? 2 : 1)
        }
    }

    private var connections: [Connection] = []
    private var paramConnections: [ParamConnection] = []

    var connectionCount: Int { connections.count + paramConnections.count }

    func connect(_ source: AudioHandler, to destination: AudioHandler, output: UInt32, input: UInt32) {
        if connections.contains(where: {
            $0.source === source && $0.destination === destination && $0.output == output && $0.input == input
        }) { return }
        connections.append(Connection(source: source, destination: destination, output: output, input: input))
    }

    func connect(_ source: AudioHandler, to destination: AudioParamHandler, output: UInt32) {
        guard !paramConnections.contains(where: {
            $0.source === source && $0.destination === destination && $0.output == output
        }) else { return }
        paramConnections.append(ParamConnection(source: source, destination: destination, output: output))
    }

    func disconnect(_ source: AudioHandler) {
        connections.removeAll { $0.source === source }
        paramConnections.removeAll { $0.source === source }
    }

    func disconnect(_ source: AudioHandler, output: UInt32) {
        connections.removeAll { $0.source === source && $0.output == output }
        paramConnections.removeAll { $0.source === source && $0.output == output }
    }

    @discardableResult
    func disconnect(_ source: AudioHandler, from destination: AudioHandler) -> Bool {
        let originalCount = connections.count
        connections.removeAll { $0.source === source && $0.destination === destination }
        return connections.count != originalCount
    }

    @discardableResult
    func disconnect(_ source: AudioHandler, from destination: AudioParamHandler) -> Bool {
        let originalCount = paramConnections.count
        paramConnections.removeAll { $0.source === source && $0.destination === destination }
        return paramConnections.count != originalCount
    }

    // Removes the handlers' connections, either way.
    func remove(_ handlers: Set<ObjectIdentifier>) {
        connections.removeAll {
            handlers.contains(ObjectIdentifier($0.source)) || handlers.contains(ObjectIdentifier($0.destination))
        }
        paramConnections.removeAll {
            handlers.contains(ObjectIdentifier($0.source)) || handlers.contains(ObjectIdentifier($0.destination.owner))
        }
    }

    func removeAll() {
        connections.removeAll()
        paramConnections.removeAll()
    }

    // The handlers that `roots` lead to, through connections to nodes and to
    // parameters, without the roots unless one leads to another.
    func handlers(downstreamOf roots: [AudioHandler]) -> [AudioHandler] {
        var outgoing: [ObjectIdentifier: [AudioHandler]] = [:]
        for connection in connections {
            outgoing[ObjectIdentifier(connection.source), default: []].append(connection.destination)
        }
        for connection in paramConnections {
            outgoing[ObjectIdentifier(connection.source), default: []].append(connection.destination.owner)
        }
        var reached: [ObjectIdentifier: AudioHandler] = [:]
        var pending = roots
        while let handler = pending.popLast() {
            for next in outgoing[ObjectIdentifier(handler)] ?? []
                where reached.updateValue(next, forKey: ObjectIdentifier(next)) == nil
            {
                pending.append(next)
            }
        }
        return Array(reached.values)
    }

    // The nodes that render, sources first, each with what it is connected
    // from. Made again for each plan, as keeping them would keep the nodes;
    // the caller clears what each is connected from once done, as a cycle
    // would otherwise keep them anyway.
    private func prepare(destination: AudioDestinationHandler) -> [RenderSlot] {
        var slots: [ObjectIdentifier: RenderSlot] = [:]
        var order: [RenderSlot] = []

        func visit(_ node: AudioHandler) -> RenderSlot {
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
            guard slot.node is DelayHandler,
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
        try makeRenderPlan(destination: destination.destinationHandler, frameCount: frameCount)
    }

    func makeRenderPlan(destination: AudioDestinationHandler, frameCount: Int) throws -> AudioRenderPlan {
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
            if let source = slot.node as? ConstantSourceHandler {
                let offset = source.offset
                let paramSources = slot.paramSources.first { $0.0 === offset }?.1 ?? []
                processor = .constant(
                    startFrame: source.scheduledStartFrame,
                    stopFrame: source.scheduledStopFrame,
                    ended: source.endedSignal,
                    parameter: offset.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let delay = slot.node as? DelayHandler {
                let delayTime = delay.delayTime
                let paramSources = slot.paramSources.first { $0.0 === delayTime }?.1 ?? []
                processor = .delay(
                    state: delay.renderState,
                    parameter: delayTime.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let node = slot.node as? GainHandler {
                let gain = node.gain
                let paramSources = slot.paramSources.first { $0.0 === gain }?.1 ?? []
                processor = .gain(
                    parameter: gain.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let filter = slot.node as? BiquadFilterHandler {
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
            } else if let source = slot.node as? AudioBufferSourceHandler {
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
            } else if let oscillator = slot.node as? OscillatorHandler {
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
            } else if let panner = slot.node as? StereoPannerHandler {
                let pan = panner.pan
                let paramSources = slot.paramSources.first { $0.0 === pan }?.1 ?? []
                processor = .stereoPanner(
                    parameter: pan.renderTimeline,
                    paramSources: paramSources.map { indices[ObjectIdentifier($0)]! }
                )
            } else if let shaper = slot.node as? WaveShaperHandler {
                processor = .waveShaper(state: shaper.renderState, curve: shaper.curve, oversample: shaper.oversample)
            } else if let source = slot.node as? MediaStreamAudioSourceHandler {
                processor = .mediaStream(state: source.renderState)
            } else if slot.node is AudioDestinationHandler {
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
        from start: AudioHandler,
        to target: AudioHandler,
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
        from node: AudioHandler,
        ignoringInputsOf cycleBreakers: Set<ObjectIdentifier>
    ) -> [AudioHandler] {
        connections.filter {
            $0.source === node && !cycleBreakers.contains(ObjectIdentifier($0.destination))
        }.map(\.destination)
            + paramConnections.compactMap { $0.source === node ? $0.destination.owner : nil }
    }

}
#endif
