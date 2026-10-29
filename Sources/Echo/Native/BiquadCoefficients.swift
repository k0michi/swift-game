// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

// A BiquadFilterNode's transfer function, H(z) = (b0 + b1 z⁻¹ + b2 z⁻²) /
// (1 + a1 z⁻¹ + a2 z⁻²): the specification's coefficients, divided by a0.
struct BiquadCoefficients: Equatable {
    var b0, b1, b2, a1, a2: Double

    // The largest Q for lowpass and highpass, in dB, for which 10^(Q/20)
    // does not overflow a float.
    static let qLimit = 20 * log10(Double(Float.greatestFiniteMagnitude))

    // `frequency` is the computedFrequency, already clamped to [0, Nyquist].
    init(type: BiquadFilterType, frequency: Double, q: Double, gain: Double, sampleRate: Double) {
        let a = pow(10, gain / 40)
        let omega = 2 * .pi * frequency / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        // Q's nominal range depends on the type: in dB for lowpass and
        // highpass, linear and not negative for the others that use it.
        let qDB = min(max(q, -Self.qLimit), Self.qLimit)
        let qLinear = min(max(q, 0), Double(Float.greatestFiniteMagnitude))
        let alphaQ = sine / (2 * qLinear)
        let alphaQDB = sine / (2 * pow(10, qDB / 20))
        // S = 1, which makes the square root √2.
        let alphaS = sine / 2 * 2.0.squareRoot()

        // The formulas that use a linear Q divide by it; at 0 the transfer
        // function is its limit as Q falls to 0, a constant.
        if qLinear == 0, let limit: Double = switch type {
            case .bandpass: 1
            case .notch: 0
            case .allpass: -1
            case .peaking: a * a
            case .lowpass, .highpass, .lowshelf, .highshelf: nil
        } {
            self.init(b0: limit, b1: 0, b2: 0, a1: 0, a2: 0)
            return
        }

        let (b0, b1, b2, a0, a1, a2): (Double, Double, Double, Double, Double, Double)
        switch type {
        case .lowpass:
            (b0, b1, b2) = ((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2)
            (a0, a1, a2) = (1 + alphaQDB, -2 * cosine, 1 - alphaQDB)
        case .highpass:
            (b0, b1, b2) = ((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2)
            (a0, a1, a2) = (1 + alphaQDB, -2 * cosine, 1 - alphaQDB)
        case .bandpass:
            (b0, b1, b2) = (alphaQ, 0, -alphaQ)
            (a0, a1, a2) = (1 + alphaQ, -2 * cosine, 1 - alphaQ)
        case .notch:
            (b0, b1, b2) = (1, -2 * cosine, 1)
            (a0, a1, a2) = (1 + alphaQ, -2 * cosine, 1 - alphaQ)
        case .allpass:
            (b0, b1, b2) = (1 - alphaQ, -2 * cosine, 1 + alphaQ)
            (a0, a1, a2) = (1 + alphaQ, -2 * cosine, 1 - alphaQ)
        case .peaking:
            (b0, b1, b2) = (1 + alphaQ * a, -2 * cosine, 1 - alphaQ * a)
            (a0, a1, a2) = (1 + alphaQ / a, -2 * cosine, 1 - alphaQ / a)
        case .lowshelf:
            let shelf = 2 * alphaS * a.squareRoot()
            (b0, b1, b2) = (
                a * ((a + 1) - (a - 1) * cosine + shelf),
                2 * a * ((a - 1) - (a + 1) * cosine),
                a * ((a + 1) - (a - 1) * cosine - shelf)
            )
            (a0, a1, a2) = ((a + 1) + (a - 1) * cosine + shelf, -2 * ((a - 1) + (a + 1) * cosine),
                            (a + 1) + (a - 1) * cosine - shelf)
        case .highshelf:
            let shelf = 2 * alphaS * a.squareRoot()
            (b0, b1, b2) = (
                a * ((a + 1) + (a - 1) * cosine + shelf),
                -2 * a * ((a - 1) + (a + 1) * cosine),
                a * ((a + 1) + (a - 1) * cosine - shelf)
            )
            (a0, a1, a2) = ((a + 1) - (a - 1) * cosine + shelf, 2 * ((a - 1) - (a + 1) * cosine),
                            (a + 1) - (a - 1) * cosine - shelf)
        }
        self.init(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        (self.b0, self.b1, self.b2, self.a1, self.a2) = (b0, b1, b2, a1, a2)
    }

    // The response at `frequency` Hz: its magnitude, and its phase in
    // radians.
    func response(at frequency: Double, sampleRate: Double) -> (magnitude: Double, phase: Double) {
        let omega = 2 * .pi * frequency / sampleRate
        // z⁻¹ = e^(-iω).
        let (c1, s1) = (cos(omega), -sin(omega))
        let (c2, s2) = (cos(2 * omega), -sin(2 * omega))
        let numerator = (real: b0 + b1 * c1 + b2 * c2, imag: b1 * s1 + b2 * s2)
        let denominator = (real: 1 + a1 * c1 + a2 * c2, imag: a1 * s1 + a2 * s2)
        let squared = denominator.real * denominator.real + denominator.imag * denominator.imag
        let real = (numerator.real * denominator.real + numerator.imag * denominator.imag) / squared
        let imag = (numerator.imag * denominator.real - numerator.real * denominator.imag) / squared
        return ((real * real + imag * imag).squareRoot(), atan2(imag, real))
    }
}
#endif
