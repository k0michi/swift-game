// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

@MainActor
public final class BiquadFilterNode: AudioNode {
    public var type: BiquadFilterType {
        didSet { context.graphDidChange() }
    }

    // With detune, a compound parameter: the filter's frequency is
    // frequency · 2^(detune / 1200), clamped to [0, Nyquist].
    public private(set) lazy var frequency = AudioParam(
        owner: self,
        defaultValue: 350,
        minValue: 0,
        maxValue: context.sampleRate / 2,
        automationRate: .aRate
    )
    public private(set) lazy var detune = AudioParam(
        owner: self,
        defaultValue: 0,
        minValue: -OscillatorNode.maximumDetune,
        maxValue: OscillatorNode.maximumDetune,
        automationRate: .aRate
    )
    // Each type clamps it further to its own nominal range.
    public private(set) lazy var Q = AudioParam(
        owner: self,
        defaultValue: 1,
        minValue: -.greatestFiniteMagnitude,
        maxValue: .greatestFiniteMagnitude,
        automationRate: .aRate
    )
    // In dB, up to about 1541: 40 log10 of the largest float.
    public private(set) lazy var gain = AudioParam(
        owner: self,
        defaultValue: 0,
        minValue: -.greatestFiniteMagnitude,
        maxValue: Float(40 * log10(Double(Float.greatestFiniteMagnitude))),
        automationRate: .aRate
    )

    let renderState = BiquadRenderState(channelCapacity: Int(AudioBuffer.maximumNumberOfChannels))
    // An IIR filter's tail-time: it rings on after its input stops.
    private let sounding = SoundingSignal()
    override var soundingSignal: SoundingSignal? { sounding }

    public init(context: BaseAudioContext, options: BiquadFilterOptions = BiquadFilterOptions()) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.channelCount ?? 2) else {
            throw WebAudioError.notSupported
        }
        try options.validate()
        type = options.type
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: options.channelCount ?? 2,
            channelCountMode: options.channelCountMode ?? .max,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        frequency.value = options.frequency
        detune.value = options.detune
        Q.value = options.Q
        gain.value = options.gain
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
        let sampleRate = Double(context.sampleRate)
        let nyquist = sampleRate / 2
        let computedFrequency = Double(frequency.value) * exp2(Double(detune.value) / 1200)
        let coefficients = BiquadCoefficients(
            type: type,
            frequency: computedFrequency.isNaN ? 0 : min(max(computedFrequency, 0), nyquist),
            q: Double(min(max(Q.value, Q.minValue), Q.maxValue)),
            gain: Double(min(max(gain.value, gain.minValue), gain.maxValue)),
            sampleRate: sampleRate
        )
        for (index, frequency) in frequencyHz.enumerated() {
            guard (0 ... nyquist).contains(Double(frequency)) else {
                magResponse[index] = .nan
                phaseResponse[index] = .nan
                continue
            }
            let response = coefficients.response(at: Double(frequency), sampleRate: sampleRate)
            magResponse[index] = Float(response.magnitude)
            phaseResponse[index] = Float(response.phase)
        }
    }

    override var audioParams: [AudioParam] { [frequency, detune, Q, gain] }
}
#endif
