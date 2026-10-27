#if os(Emscripten)
@MainActor
public class AudioNode {
    public let context: BaseAudioContext
    public let numberOfInputs: UInt32
    public let numberOfOutputs: UInt32

    public var channelCount: UInt32 {
        UInt32(object.number("channelCount"))
    }
    public var channelCountMode: ChannelCountMode {
        ChannelCountMode(rawValue: object.string("channelCountMode"))!
    }
    public var channelInterpretation: ChannelInterpretation {
        ChannelInterpretation(rawValue: object.string("channelInterpretation"))!
    }

    let object: JSObjectReference

    init(context: BaseAudioContext, object: JSObjectReference) {
        self.context = context
        self.object = object
        numberOfInputs = UInt32(object.number("numberOfInputs"))
        numberOfOutputs = UInt32(object.number("numberOfOutputs"))
    }

    public func setChannelCount(_ channelCount: UInt32) throws {
        try object.set("channelCount", Double(channelCount))
    }

    public func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        try object.set("channelCountMode", channelCountMode.rawValue)
    }

    public func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        // The browser throws only for strings outside the enumeration.
        try? object.set("channelInterpretation", channelInterpretation.rawValue)
    }

    @discardableResult
    public func connect(_ destinationNode: AudioNode, output: UInt32 = 0, input: UInt32 = 0) throws -> AudioNode {
        try object.call("connect", destinationNode.object, [Double(output), Double(input)])
        return destinationNode
    }

    public func disconnect() {
        try? object.call("disconnect")
    }

    public func disconnect(output: UInt32) throws {
        try object.call("disconnect", nil, [Double(output)])
    }

    public func disconnect(_ destinationNode: AudioNode) throws {
        try object.call("disconnect", destinationNode.object)
    }

    public func connect(_ destinationParam: AudioParam, output: UInt32 = 0) throws {
        try object.call("connect", destinationParam.object, [Double(output)])
    }

    public func disconnect(_ destinationParam: AudioParam) throws {
        try object.call("disconnect", destinationParam.object)
    }
}
#endif
