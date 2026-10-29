// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
public final class WaveShaperNode: AudioNode {
    // nil passes the input through unchanged.
    public private(set) var curve: [Float]?

    public var oversample: OverSampleType {
        didSet { context.graphDidChange() }
    }

    // [[curve set]]: whether a curve has been set, after which only nil may be.
    private var curveSet = false
    let renderState: WaveShaperRenderState

    public init(context: BaseAudioContext, options: WaveShaperOptions = WaveShaperOptions()) throws {
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.channelCount ?? 2) else {
            throw WebAudioError.notSupported
        }
        // The option is a sequence<float>, which takes only finite values.
        if let curve = options.curve, !curve.allSatisfy(\.isFinite) {
            throw WebAudioError.rangeError
        }
        oversample = options.oversample
        renderState = WaveShaperRenderState(
            channelCapacity: Int(AudioBuffer.maximumNumberOfChannels),
            quantumSize: Int(context.renderQuantumSize)
        )
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: options.channelCount ?? 2,
            channelCountMode: options.channelCountMode ?? .max,
            channelInterpretation: options.channelInterpretation ?? .speakers
        )
        if let curve = options.curve {
            try setCurve(curve)
        }
    }

    // Sets the curve attribute. The array is a value, so later changes to the
    // caller's copy have no effect, as the attribute's internal copy has none.
    public func setCurve(_ curve: [Float]?) throws {
        if let curve {
            guard curve.count >= 2, !curveSet else { throw WebAudioError.invalidState }
            curveSet = true
        }
        self.curve = curve
        context.graphDidChange()
    }
}
#endif
