// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

@MainActor
public final class OscillatorNode: AudioNode {
    // "custom" comes only from a PeriodicWave.
    public private(set) var type: OscillatorType

    // With detune, a compound parameter: the oscillator's frequency is
    // frequency · 2^(detune / 1200), clamped to the Nyquist frequency.
    public private(set) lazy var frequency = AudioParam(
        owner: self,
        defaultValue: 440,
        minValue: -context.sampleRate / 2,
        maxValue: context.sampleRate / 2,
        automationRate: .aRate
    )
    public private(set) lazy var detune = AudioParam(
        owner: self,
        defaultValue: 0,
        minValue: -Self.maximumDetune,
        maxValue: Self.maximumDetune,
        automationRate: .aRate
    )

    // About 153600 cents: 1200 log2 of the largest float.
    static let maximumDetune = Float(1200 * log2(Double(Float.greatestFiniteMagnitude)))

    private var periodicWave: PeriodicWave?
    private(set) var startTime: Double?
    private(set) var stopTime: Double?
    let renderState = OscillatorRenderState()

    public init(context: BaseAudioContext, options: OscillatorOptions = OscillatorOptions()) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.channelCount ?? 2) else {
            throw WebAudioError.notSupported
        }
        try options.validate()
        type = options.periodicWave == nil ? options.type : .custom
        periodicWave = options.periodicWave
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            channelCount: options.channelCount ?? 2,
            channelCountMode: options.channelCountMode ?? .max,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        frequency.value = options.frequency
        detune.value = options.detune
    }

    // Sets the type attribute, keeping the phase. "custom" is set with a
    // PeriodicWave instead.
    public func setType(_ type: OscillatorType) throws {
        guard type != .custom else { throw WebAudioError.invalidState }
        self.type = type
        periodicWave = nil
        context.graphDidChange()
    }

    public func setPeriodicWave(_ periodicWave: PeriodicWave) {
        self.periodicWave = periodicWave
        type = .custom
        context.graphDidChange()
    }

    public func start(_ when: Double = 0) throws {
        guard startTime == nil else { throw WebAudioError.invalidState }
        startTime = try scheduledTime(when)
        context.graphDidChange()
    }

    public func stop(_ when: Double = 0) throws {
        guard startTime != nil else { throw WebAudioError.invalidState }
        stopTime = try scheduledTime(when)
        context.graphDidChange()
    }

    var waveTable: WaveTable {
        periodicWave?.waveTable ?? .builtIn(type)
    }

    override var audioParams: [AudioParam] { [frequency, detune] }

    // The time exactly, as the phase depends on it, or now for a time
    // already past.
    private func scheduledTime(_ when: Double) throws -> Double {
        guard when.isFinite, when >= 0 else { throw WebAudioError.rangeError }
        return max(when, context.currentTime)
    }
}
#endif
