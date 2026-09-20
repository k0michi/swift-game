final class RenderGraph {
    let sampleRate: Float
    let renderQuantumSize: UInt32
    let clock = AudioRenderClock()

    private(set) var nodes: [AudioNodeID: RenderNodeState] = [:]
    private(set) var params: [AudioParamID: RenderParamState] = [:]
    private(set) var nodeConnections: Set<RenderNodeConnection> = []
    private(set) var paramConnections: Set<RenderParamConnection> = []
    private var destinationID: AudioNodeID?

    init(sampleRate: Float, renderQuantumSize: UInt32) {
        self.sampleRate = sampleRate
        self.renderQuantumSize = renderQuantumSize
    }

    func apply(_ message: ControlMessage) {
        switch message {
        case .registerNode(let node):
            nodes[node.id] = node
            if case .destination = node.kind { destinationID = node.id }
        case .registerParam(let param):
            params[param.id] = param
        case .connectNodes(let connection):
            nodeConnections.insert(connection)
        case .connectParam(let connection):
            paramConnections.insert(connection)
        case .disconnectAll(let source):
            nodeConnections = nodeConnections.filter { $0.source != source }
            paramConnections = paramConnections.filter { $0.source != source }
        case .disconnectOutput(let source, let output):
            nodeConnections = nodeConnections.filter { $0.source != source || $0.output != output }
            paramConnections = paramConnections.filter { $0.source != source || $0.output != output }
        case .disconnectNodes(let source, let destination, let requestedOutput, let requestedInput):
            nodeConnections = nodeConnections.filter { connection in
                !(connection.source == source
                    && connection.destination == destination
                    && (requestedOutput.map { connection.output == $0 } ?? true)
                    && (requestedInput.map { connection.input == $0 } ?? true))
            }
        case .disconnectParam(let source, let destination, let requestedOutput):
            paramConnections = paramConnections.filter { connection in
                !(connection.source == source
                    && connection.destination == destination
                    && (requestedOutput.map { connection.output == $0 } ?? true))
            }
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
        }
    }

    func render(into output: inout AudioBus, frameCount: Int) throws {
        guard frameCount >= 0, frameCount <= Int(renderQuantumSize), frameCount <= output.frameCapacity else {
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
        clock.advance(by: frameCount)
    }
}
