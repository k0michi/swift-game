#if os(Emscripten)
@MainActor
public final class OscillatorNode: AudioScheduledSourceNode {
    public var type: OscillatorType {
        OscillatorType(rawValue: object.string("type")) ?? .sine
    }

    public private(set) lazy var frequency = AudioParam(context: context, object: object.object("frequency")!)
    public private(set) lazy var detune = AudioParam(context: context, object: object.object("detune")!)

    public init(context: BaseAudioContext, options: OscillatorOptions = OscillatorOptions()) throws {
        try options.validate()
        // A PeriodicWave cannot go through JSON, so the node starts as a sine
        // and takes the wave once made, which is the same.
        var fields: [(String, JSONValue)] = [
            ("type", .string(options.periodicWave == nil ? options.type.rawValue : OscillatorType.sine.rawValue)),
            ("frequency", .number(Double(options.frequency))),
            ("detune", .number(Double(options.detune))),
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
            object: try JSObjectReference.new("OscillatorNode", context: context.object, options: fields)
        )
        if let periodicWave = options.periodicWave {
            setPeriodicWave(periodicWave)
        }
    }

    // Sets the type attribute, keeping the phase. "custom" is set with a
    // PeriodicWave instead.
    public func setType(_ type: OscillatorType) throws {
        try object.set("type", type.rawValue)
    }

    public func setPeriodicWave(_ periodicWave: PeriodicWave) {
        // The browser throws only for what is not a PeriodicWave.
        try! object.call("setPeriodicWave", periodicWave.object)
    }
}
#endif
