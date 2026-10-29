// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// What a node is inside its context: its settings, parameters, connections
// and rendering state. The context keeps it while it may sound; the node the
// caller holds only refers to it.
@MainActor
class AudioHandler {
    // The context keeps every handler, and the caller's node keeps the
    // context, so the context outlives it.
    unowned let context: BaseAudioContext
    let numberOfInputs: UInt32
    let numberOfOutputs: UInt32

    private(set) var channelCount: UInt32
    private(set) var channelCountMode: ChannelCountMode
    private(set) var channelInterpretation: ChannelInterpretation

    // The caller's node, while the caller keeps it.
    weak var node: AudioNode?

    init(
        context: BaseAudioContext,
        numberOfInputs: UInt32,
        numberOfOutputs: UInt32,
        channelCount: UInt32,
        channelCountMode: ChannelCountMode,
        channelInterpretation: ChannelInterpretation
    ) {
        self.context = context
        self.numberOfInputs = numberOfInputs
        self.numberOfOutputs = numberOfOutputs
        self.channelCount = channelCount
        self.channelCountMode = channelCountMode
        self.channelInterpretation = channelInterpretation
        // The context keeps its destination itself.
        if !(self is AudioDestinationHandler) {
            context.register(self)
        }
    }

    var graph: AudioGraph { context.graph }

    var audioParams: [AudioParamHandler] { [] }

    // For a node with a tail-time, whether it still sounds.
    var soundingSignal: SoundingSignal? { nil }

    // Whether it may sound without any input: a source that has started and
    // not ended, or a live track.
    var playsOnItsOwn: Bool { false }

    // Whether the caller still holds its node or one of its parameters.
    var isReferenced: Bool {
        node != nil || audioParams.contains { $0.handle != nil }
    }

    func setChannelCount(_ channelCount: UInt32) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(channelCount) else {
            throw WebAudioError.indexSize
        }
        self.channelCount = channelCount
        context.graphDidChange()
    }

    func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        self.channelCountMode = channelCountMode
        context.graphDidChange()
    }

    func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        self.channelInterpretation = channelInterpretation
        context.graphDidChange()
    }

    func connect(_ destination: AudioHandler, output: UInt32, input: UInt32) throws {
        guard context === destination.context else { throw WebAudioError.invalidAccess }
        guard output < numberOfOutputs, input < destination.numberOfInputs else {
            throw WebAudioError.indexSize
        }
        graph.connect(self, to: destination, output: output, input: input)
        context.graphDidChange()
    }

    func connect(_ destination: AudioParamHandler, output: UInt32) throws {
        guard context === destination.context else { throw WebAudioError.invalidAccess }
        guard output < numberOfOutputs else { throw WebAudioError.indexSize }
        graph.connect(self, to: destination, output: output)
        context.graphDidChange()
    }

    func disconnect() {
        graph.disconnect(self)
        context.graphDidChange()
    }

    func disconnect(output: UInt32) throws {
        guard output < numberOfOutputs else { throw WebAudioError.indexSize }
        graph.disconnect(self, output: output)
        context.graphDidChange()
    }

    func disconnect(_ destination: AudioHandler) throws {
        guard graph.disconnect(self, from: destination) else { throw WebAudioError.invalidAccess }
        context.graphDidChange()
    }

    func disconnect(_ destination: AudioParamHandler) throws {
        guard graph.disconnect(self, from: destination) else { throw WebAudioError.invalidAccess }
        context.graphDidChange()
    }
}

// The node the caller holds, which keeps its context and forwards to its
// handler. Letting go of it lets the context let go of the handler, once
// nothing that may sound leads to it.
@MainActor
public class AudioNode {
    public let context: BaseAudioContext
    let handler: AudioHandler

    init(handler: AudioHandler) {
        self.handler = handler
        context = handler.context
        handler.node = self
    }

    public var numberOfInputs: UInt32 { handler.numberOfInputs }
    public var numberOfOutputs: UInt32 { handler.numberOfOutputs }
    public var channelCount: UInt32 { handler.channelCount }
    public var channelCountMode: ChannelCountMode { handler.channelCountMode }
    public var channelInterpretation: ChannelInterpretation { handler.channelInterpretation }

    public func setChannelCount(_ channelCount: UInt32) throws {
        try handler.setChannelCount(channelCount)
    }

    public func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        try handler.setChannelCountMode(channelCountMode)
    }

    public func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        handler.setChannelInterpretation(channelInterpretation)
    }

    @discardableResult
    public func connect(_ destinationNode: AudioNode, output: UInt32 = 0, input: UInt32 = 0) throws -> AudioNode {
        try handler.connect(destinationNode.handler, output: output, input: input)
        return destinationNode
    }

    public func connect(_ destinationParam: AudioParam, output: UInt32 = 0) throws {
        try handler.connect(destinationParam.handler, output: output)
    }

    public func disconnect() {
        handler.disconnect()
    }

    public func disconnect(output: UInt32) throws {
        try handler.disconnect(output: output)
    }

    public func disconnect(_ destinationNode: AudioNode) throws {
        try handler.disconnect(destinationNode.handler)
    }

    public func disconnect(_ destinationParam: AudioParam) throws {
        try handler.disconnect(destinationParam.handler)
    }

    // TODO: Add the remaining Web IDL disconnect overloads.
}
#endif
