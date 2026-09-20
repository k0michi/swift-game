final class RenderGraph {
    let sampleRate: Float
    let renderQuantumSize: UInt32
    let clock = AudioRenderClock()

    private(set) var nodes: [AudioNodeID: RenderNodeState] = [:]
    private(set) var params: [AudioParamID: RenderParamState] = [:]
    private(set) var nodeConnections: Set<RenderNodeConnection> = []
    private(set) var paramConnections: Set<RenderParamConnection> = []
    private(set) var renderOrder: [AudioNodeID] = []
    private(set) var mutedNodeIDs: Set<AudioNodeID> = []

    private var destinationID: AudioNodeID?
    private var renderPlan: RenderPlan?

    init(sampleRate: Float, renderQuantumSize: UInt32) {
        self.sampleRate = sampleRate
        self.renderQuantumSize = renderQuantumSize
    }

    func apply(_ message: ControlMessage) {
        switch message {
        case .registerNode(let node):
            nodes[node.id] = node
            if node.processor is RenderDestinationProcessor { destinationID = node.id }
            invalidateRenderPlan()
        case .registerParam(let param):
            params[param.id] = param
        case .connectNodes(let connection):
            nodeConnections.insert(connection)
            invalidateRenderPlan()
        case .connectParam(let connection):
            paramConnections.insert(connection)
            invalidateRenderPlan()
        case .disconnectAll(let source):
            nodeConnections = nodeConnections.filter { $0.source != source }
            paramConnections = paramConnections.filter { $0.source != source }
            invalidateRenderPlan()
        case .disconnectOutput(let source, let output):
            nodeConnections = nodeConnections.filter { $0.source != source || $0.output != output }
            paramConnections = paramConnections.filter { $0.source != source || $0.output != output }
            invalidateRenderPlan()
        case .disconnectNodes(let source, let destination, let requestedOutput, let requestedInput):
            nodeConnections = nodeConnections.filter { connection in
                !(connection.source == source
                    && connection.destination == destination
                    && (requestedOutput.map { connection.output == $0 } ?? true)
                    && (requestedInput.map { connection.input == $0 } ?? true))
            }
            invalidateRenderPlan()
        case .disconnectParam(let source, let destination, let requestedOutput):
            paramConnections = paramConnections.filter { connection in
                !(connection.source == source
                    && connection.destination == destination
                    && (requestedOutput.map { connection.output == $0 } ?? true))
            }
            invalidateRenderPlan()
        case .setChannelCount(let id, let value):
            nodes[id]?.channelCount = value
        case .setChannelCountMode(let id, let value):
            nodes[id]?.channelCountMode = value
        case .setChannelInterpretation(let id, let value):
            nodes[id]?.channelInterpretation = value
        case .setParamValue(let id, let value):
            params[id]?.value = value
        case .setAutomationRate(let id, let value):
            params[id]?.automationRate = value
        case .setOscillatorType(let id, let type):
            nodes[id]?.processor.apply(.setOscillatorType(type))
        case .startSource(let id, let when):
            nodes[id]?.processor.apply(.start(when))
        case .stopSource(let id, let when):
            nodes[id]?.processor.apply(.stop(when))
        }
    }

    func render(into output: inout AudioBus, frameCount: Int) throws {
        guard frameCount >= 0,
              frameCount <= Int(renderQuantumSize),
              frameCount <= output.frameCapacity
        else {
            throw AudioRenderError.invalidFrameCount(frameCount)
        }
        let requiredChannels = destinationID.flatMap { nodes[$0] }.map { Int($0.channelCount) } ?? 1
        guard output.numberOfChannels >= requiredChannels else {
            throw AudioRenderError.insufficientOutputChannels(
                required: requiredChannels,
                actual: output.numberOfChannels
            )
        }

        output.clear(frameCount: frameCount)
        guard frameCount > 0, let destinationID else { return }
        let plan = currentRenderPlan()

        let context = RenderProcessContext(
            sampleRate: sampleRate,
            frameCount: frameCount,
            currentFrame: clock.renderedFrames,
            params: params
        )
        var outputs: [AudioNodeID: AudioBus] = [:]
        for id in plan.mutedNodeIDs {
            guard let node = nodes[id] else { continue }
            outputs[id] = AudioBus(
                numberOfChannels: max(1, Int(node.channelCount)),
                frameCapacity: frameCount
            )
        }
        for id in plan.order {
            guard let node = nodes[id] else { continue }
            let sources = nodeConnections.lazy
                .filter { $0.destination == id && $0.input == 0 }
                .compactMap { outputs[$0.source] }
            let inputChannelCount = node.processor is RenderDestinationProcessor
                ? Int(node.channelCount)
                : max(1, sources.map(\.numberOfChannels).max() ?? 1)
            var input = AudioBus(numberOfChannels: inputChannelCount, frameCapacity: frameCount)
            for source in sources {
                mix(source, into: &input, frameCount: frameCount)
            }
            let outputChannelCount = max(
                1,
                node.processor.outputChannelCount(
                    inputChannelCount: inputChannelCount,
                    node: node
                )
            )
            var nodeOutput = AudioBus(
                numberOfChannels: outputChannelCount,
                frameCapacity: frameCount
            )
            node.processor.process(context: context, input: input, output: &nodeOutput)
            outputs[id] = nodeOutput
        }

        if let destinationOutput = outputs[destinationID] {
            copy(destinationOutput, into: &output, frameCount: frameCount)
        }
        clock.advance(by: frameCount)
    }

    private func invalidateRenderPlan() {
        renderPlan = nil
        renderOrder = []
        mutedNodeIDs = []
    }

    private func currentRenderPlan() -> RenderPlan {
        if let renderPlan { return renderPlan }
        let plan = RenderPlanBuilder(
            nodes: nodes,
            nodeConnections: nodeConnections,
            paramConnections: paramConnections
        ).build()
        renderOrder = plan.order
        mutedNodeIDs = plan.mutedNodeIDs
        renderPlan = plan
        return plan
    }

    private func mix(_ source: AudioBus, into destination: inout AudioBus, frameCount: Int) {
        for frame in 0..<frameCount {
            if source.numberOfChannels == destination.numberOfChannels {
                for channel in 0..<destination.numberOfChannels {
                    destination[channel, frame] += source[channel, frame]
                }
            } else if source.numberOfChannels == 1 {
                for channel in 0..<destination.numberOfChannels {
                    destination[channel, frame] += source[0, frame]
                }
            } else if destination.numberOfChannels == 1 {
                let sum = (0..<source.numberOfChannels).reduce(Float.zero) {
                    $0 + source[$1, frame]
                }
                destination[0, frame] += sum / Float(source.numberOfChannels)
            } else {
                for channel in 0..<min(source.numberOfChannels, destination.numberOfChannels) {
                    destination[channel, frame] += source[channel, frame]
                }
            }
        }
    }

    private func copy(_ source: AudioBus, into destination: inout AudioBus, frameCount: Int) {
        for channel in 0..<min(source.numberOfChannels, destination.numberOfChannels) {
            for frame in 0..<frameCount {
                destination[channel, frame] = source[channel, frame]
            }
        }
    }
}
