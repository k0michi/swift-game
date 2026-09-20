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

        var parameterValues: [AudioParamID: [Float]] = [:]
        var outputs: [AudioNodeID: [AudioBus]] = [:]
        for id in plan.mutedNodeIDs {
            guard let node = nodes[id] else { continue }
            outputs[id] = (0..<max(1, Int(node.numberOfOutputs))).map { output in
                AudioBus(
                    numberOfChannels: max(
                        1,
                        node.processor.outputChannelCount(
                            output: output,
                            inputChannelCounts: [],
                            node: node
                        )
                    ),
                    frameCapacity: frameCount
                )
            }
        }
        for id in plan.order {
            guard let node = nodes[id] else { continue }
            for parameterID in node.processor.parameterIDs {
                parameterValues[parameterID] = computeParameterValues(
                    id: parameterID,
                    outputs: outputs,
                    frameCount: frameCount
                )
            }
            let inputs = (0..<Int(node.numberOfInputs)).map { input in
                makeInput(
                    node: node,
                    input: input,
                    outputs: outputs,
                    frameCount: frameCount
                )
            }
            let inputChannelCounts = inputs.map(\.numberOfChannels)
            let outputCount = max(1, Int(node.numberOfOutputs))
            var nodeOutputs = (0..<outputCount).map { output in
                AudioBus(
                    numberOfChannels: max(
                        1,
                        node.processor.outputChannelCount(
                            output: output,
                            inputChannelCounts: inputChannelCounts,
                            node: node
                        )
                    ),
                    frameCapacity: frameCount
                )
            }
            let context = RenderProcessContext(
                sampleRate: sampleRate,
                frameCount: frameCount,
                currentFrame: clock.renderedFrames,
                parameterValues: parameterValues
            )
            node.processor.process(context: context, inputs: inputs, outputs: &nodeOutputs)
            outputs[id] = nodeOutputs
        }

        if let destinationOutput = outputs[destinationID]?.first {
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

    private func makeInput(
        node: RenderNodeState,
        input: Int,
        outputs: [AudioNodeID: [AudioBus]],
        frameCount: Int
    ) -> AudioBus {
        let sources = nodeConnections.lazy
            .filter { $0.destination == node.id && $0.input == UInt32(input) }
            .compactMap { connection -> AudioBus? in
                guard let sourceOutputs = outputs[connection.source],
                      Int(connection.output) < sourceOutputs.count
                else { return nil }
                return sourceOutputs[Int(connection.output)]
            }
        let maximumChannelCount = sources.map(\.numberOfChannels).max() ?? 1
        let channelCount = switch node.channelCountMode {
        case .max:
            maximumChannelCount
        case .clampedMax:
            min(maximumChannelCount, Int(node.channelCount))
        case .explicit:
            Int(node.channelCount)
        }
        var result = AudioBus(numberOfChannels: max(1, channelCount), frameCapacity: frameCount)
        for source in sources {
            AudioBusMixer.mix(
                source,
                into: &result,
                interpretation: node.channelInterpretation,
                frameCount: frameCount
            )
        }
        return result
    }

    private func computeParameterValues(
        id: AudioParamID,
        outputs: [AudioNodeID: [AudioBus]],
        frameCount: Int
    ) -> [Float] {
        guard let param = params[id] else { return Array(repeating: 0, count: frameCount) }
        let connections = paramConnections.filter { $0.destination == id }
        var values = Array(repeating: param.value, count: frameCount)
        for connection in connections {
            guard let sourceOutputs = outputs[connection.source],
                  Int(connection.output) < sourceOutputs.count
            else { continue }
            let source = sourceOutputs[Int(connection.output)]
            for frame in 0..<frameCount {
                values[frame] += downMixToMono(source, frame: frame)
            }
        }
        for frame in values.indices {
            if values[frame].isNaN { values[frame] = param.defaultValue }
            values[frame] = min(param.maxValue, max(param.minValue, values[frame]))
        }
        if param.automationRate == .kRate, let first = values.first {
            values = Array(repeating: first, count: frameCount)
        }
        return values
    }

    private func downMixToMono(_ source: AudioBus, frame: Int) -> Float {
        AudioBusMixer.downMixToMono(source, frame: frame)
    }

    private func copy(_ source: AudioBus, into destination: inout AudioBus, frameCount: Int) {
        for channel in 0..<min(source.numberOfChannels, destination.numberOfChannels) {
            for frame in 0..<frameCount {
                destination[channel, frame] = source[channel, frame]
            }
        }
    }
}
