#if os(Emscripten)
@MainActor
public final class GainNode: AudioNode {
    public private(set) lazy var gain = AudioParam(context: context, object: object.object("gain")!)

    public init(context: BaseAudioContext, options: GainOptions = GainOptions()) throws {
        // The option is a float, which takes only finite values. JSON would
        // turn the others into null, which the browser takes as 0.
        guard options.gain.isFinite else { throw WebAudioError.rangeError }
        var fields: [(String, JSONValue)] = [("gain", .number(Double(options.gain)))]
        if let channelCount = options.channelCount {
            fields.append(("channelCount", .number(Double(channelCount))))
        }
        if let channelCountMode = options.channelCountMode {
            fields.append(("channelCountMode", .string(channelCountMode.rawValue)))
        }
        if let channelInterpretation = options.channelInterpretation {
            fields.append(("channelInterpretation", .string(channelInterpretation.rawValue)))
        }
        super.init(context: context, object: try JSObjectReference.new("GainNode", context: context.object, options: fields))
    }
}
#endif
