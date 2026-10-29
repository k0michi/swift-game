// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// A BiquadFilterNode's filter state, x(n-1), x(n-2), y(n-1) and y(n-2) for
// each channel, which starts at 0 and carries from one render quantum to the
// next. Used only by the rendering thread.
final class BiquadRenderState: @unchecked Sendable {
    private var history: [Double]
    private var coefficients: BiquadCoefficients?
    private var coefficientsKey: (type: BiquadFilterType, frequency: Double, q: Double, gain: Double)?

    init(channelCapacity: Int) {
        history = [Double](repeating: 0, count: 4 * channelCapacity)
    }

    // The output has as many channels as the input. `parameters` gives the
    // computedFrequency, Q and gain of each frame of the quantum.
    func render(
        input: AudioRenderQuantum,
        output: AudioRenderQuantum,
        type: BiquadFilterType,
        sampleRate: Float,
        parameters: (Int) -> (frequency: Double, q: Double, gain: Double)
    ) {
        output.setChannelCount(input.channelCount)
        for index in 0 ..< input.frameCount {
            let coefficients = coefficients(type: type, sampleRate: sampleRate, parameters(index))
            for channel in 0 ..< input.channelCount {
                let base = 4 * channel
                let x = Double(input.channelData(channel)[index])
                let y = coefficients.b0 * x + coefficients.b1 * history[base] + coefficients.b2 * history[base + 1]
                    - coefficients.a1 * history[base + 2] - coefficients.a2 * history[base + 3]
                history[base + 1] = history[base]
                history[base] = x
                history[base + 3] = history[base + 2]
                history[base + 2] = y
                output.channelData(channel)[index] = Float(y)
            }
        }
    }

    // The coefficients, made again only when a parameter changes.
    private func coefficients(
        type: BiquadFilterType,
        sampleRate: Float,
        _ parameters: (frequency: Double, q: Double, gain: Double)
    ) -> BiquadCoefficients {
        if let coefficients, let key = coefficientsKey, key.type == type, key.frequency == parameters.frequency,
           key.q == parameters.q, key.gain == parameters.gain
        {
            return coefficients
        }
        let coefficients = BiquadCoefficients(
            type: type, frequency: parameters.frequency, q: parameters.q, gain: parameters.gain,
            sampleRate: Double(sampleRate)
        )
        self.coefficients = coefficients
        coefficientsKey = (type, parameters.frequency, parameters.q, parameters.gain)
        return coefficients
    }
}
#endif
