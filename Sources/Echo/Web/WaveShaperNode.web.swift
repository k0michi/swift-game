#if os(Emscripten)
@MainActor
public final class WaveShaperNode: AudioNode {
    // nil passes the input through unchanged. Only Echo sets the browser's,
    // so this copy stays the same.
    public private(set) var curve: [Float]?

    // [[curve set]], kept here because browsers predate it: Chromium lets a
    // curve be set again, and throws InvalidAccessError for one too short.
    private var curveSet = false

    public var oversample: OverSampleType {
        get { OverSampleType(rawValue: object.string("oversample")) ?? .none }
        // The browser throws only for strings that are not an OverSampleType.
        set { try! object.set("oversample", newValue.rawValue) }
    }

    public init(context: BaseAudioContext, options: WaveShaperOptions = WaveShaperOptions()) throws {
        // The option is a sequence<float>, which takes only finite values. JSON
        // would turn the others into null, which the browser takes as 0.
        if let curve = options.curve {
            guard curve.allSatisfy(\.isFinite) else { throw WebAudioError.rangeError }
            guard curve.count >= 2 else { throw WebAudioError.invalidState }
        }
        var fields: [(String, JSONValue)] = [("oversample", .string(options.oversample.rawValue))]
        if let curve = options.curve {
            fields.append(("curve", .array(curve.map { .number(Double($0)) })))
        }
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
            object: try JSObjectReference.new("WaveShaperNode", context: context.object, options: fields)
        )
        curve = options.curve
        curveSet = options.curve != nil
    }

    // Sets the curve attribute, which keeps a copy of the array.
    public func setCurve(_ curve: [Float]?) throws {
        if let curve {
            guard curve.count >= 2, !curveSet else { throw WebAudioError.invalidState }
        }
        try object.set("curve", floats: curve)
        if curve != nil {
            curveSet = true
        }
        self.curve = curve
    }
}
#endif
