#if os(Emscripten)
@MainActor
public final class StereoPannerNode: AudioNode {
    public private(set) lazy var pan = AudioParam(context: context, object: object.object("pan")!)

    // The browser throws NotSupportedError itself for more than two channels
    // or the "max" channel count mode.
    public init(context: BaseAudioContext, options: StereoPannerOptions = StereoPannerOptions()) throws {
        // The option is a float, which takes only finite values. JSON would
        // turn the others into null, which the browser takes as 0.
        guard options.pan.isFinite else { throw WebAudioError.rangeError }
        var fields: [(String, JSONValue)] = [("pan", .number(Double(options.pan)))]
        if let channelCount = options.channelCount {
            fields.append(("channelCount", .number(Double(channelCount))))
        }
        if let channelCountMode = options.channelCountMode {
            fields.append(("channelCountMode", .string(channelCountMode.rawValue)))
        }
        if let channelInterpretation = options.channelInterpretation {
            fields.append(("channelInterpretation", .string(channelInterpretation.rawValue)))
        }
        super.init(
            context: context,
            object: try JSObjectReference.new("StereoPannerNode", context: context.object, options: fields)
        )
    }
}
#endif
