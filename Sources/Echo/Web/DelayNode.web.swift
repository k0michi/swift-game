#if os(Emscripten)
@MainActor
public final class DelayNode: AudioNode {
    public private(set) lazy var delayTime = AudioParam(context: context, object: object.object("delayTime")!)

    public let maxDelayTime: Double

    public init(context: BaseAudioContext, options: DelayOptions = DelayOptions()) throws {
        var fields: [(String, JSONValue)] = [
            ("maxDelayTime", .number(options.maxDelayTime)),
            ("delayTime", .number(options.delayTime)),
        ]
        if let channelCount = options.channelCount {
            fields.append(("channelCount", .number(Double(channelCount))))
        }
        if let channelCountMode = options.channelCountMode {
            fields.append(("channelCountMode", .string(channelCountMode.rawValue)))
        }
        if let channelInterpretation = options.channelInterpretation {
            fields.append(("channelInterpretation", .string(channelInterpretation.rawValue)))
        }
        maxDelayTime = options.maxDelayTime
        super.init(context: context, object: try JSObjectReference.new("DelayNode", context: context.object, options: fields))
    }
}
#endif
