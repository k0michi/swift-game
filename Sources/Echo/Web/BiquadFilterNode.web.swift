#if os(Emscripten)
@MainActor
public final class BiquadFilterNode: AudioNode {
    public var type: BiquadFilterType {
        get { BiquadFilterType(rawValue: object.string("type")) ?? .lowpass }
        // The browser throws only for strings that are not a BiquadFilterType.
        set { try! object.set("type", newValue.rawValue) }
    }

    public private(set) lazy var frequency = AudioParam(context: context, object: object.object("frequency")!)
    public private(set) lazy var detune = AudioParam(context: context, object: object.object("detune")!)
    public private(set) lazy var Q = AudioParam(context: context, object: object.object("Q")!)
    public private(set) lazy var gain = AudioParam(context: context, object: object.object("gain")!)

    public init(context: BaseAudioContext, options: BiquadFilterOptions = BiquadFilterOptions()) throws {
        try options.validate()
        var fields: [(String, JSONValue)] = [
            ("type", .string(options.type.rawValue)),
            ("Q", .number(Double(options.Q))),
            ("detune", .number(Double(options.detune))),
            ("frequency", .number(Double(options.frequency))),
            ("gain", .number(Double(options.gain))),
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
        super.init(
            context: context,
            object: try JSObjectReference.new("BiquadFilterNode", context: context.object, options: fields)
        )
    }

    // The response at each of `frequencyHz`, from the parameters' current
    // values: its linear magnitude and its phase in radians, or NaN for a
    // frequency outside [0, Nyquist].
    public func getFrequencyResponse(
        _ frequencyHz: [Float],
        _ magResponse: inout [Float],
        _ phaseResponse: inout [Float]
    ) throws {
        guard magResponse.count == frequencyHz.count, phaseResponse.count == frequencyHz.count else {
            throw WebAudioError.invalidAccess
        }
        try object.getFrequencyResponse(frequencyHz, &magResponse, &phaseResponse)
    }
}
#endif
