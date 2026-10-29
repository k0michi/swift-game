// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

// One period of a PeriodicWave, band-limited: tables of the same waveform
// with fewer and fewer partials, an octave apart, so that an oscillator can
// play it at any frequency without partials above the Nyquist frequency.
final class WaveTable: Sendable {
    static let size = 4096
    // The partials of each table: as many as fit in one, then half as many
    // each time down to the fundamental alone.
    static let partialCounts: [Int] = [size / 2 - 1] + sequence(first: size / 4) { $0 > 1 ? $0 / 2 : nil }

    private let tables: [[Float]]

    // `real` and `imag` are a PeriodicWave's [[real]] and [[imag]], whose
    // partials beyond what a table holds are left out.
    init(real: [Float], imag: [Float], normalize: Bool) {
        let available = min(real.count - 1, Self.partialCounts[0])
        var tables: [[Float]] = []
        for count in Self.partialCounts {
            if count >= available, let last = tables.last {
                tables.append(last)
            } else {
                tables.append(Self.synthesize(real: real, imag: imag, partials: min(count, available)))
            }
        }
        // The specification's normalization: one factor, from the waveform
        // with every partial, for all the tables.
        if normalize, let peak = tables.first?.map(abs).max(), peak > 0 {
            tables = tables.map { $0.map { $0 / peak } }
        }
        self.tables = tables
    }

    // The table for the oscillator's built-in types, which are the Fourier
    // series the specification gives, normalized.
    @MainActor
    static func builtIn(_ type: OscillatorType) -> WaveTable {
        if let table = builtIns[type] { return table }
        let count = partialCounts[0] + 1
        let imag = (0 ..< count).map { n -> Float in
            let n = Double(n)
            guard n > 0 else { return 0 }
            return switch type {
            case .sine: n == 1 ? 1 : 0
            case .square: Float(2 / (n * .pi) * (1 - pow(-1, n)))
            case .sawtooth: Float(pow(-1, n + 1) * 2 / (n * .pi))
            case .triangle: Float(8 * sin(n * .pi / 2) / pow(.pi * n, 2))
            case .custom: preconditionFailure("A custom waveform comes from a PeriodicWave")
            }
        }
        let table = WaveTable(real: [Float](repeating: 0, count: count), imag: imag, normalize: true)
        builtIns[type] = table
        return table
    }

    @MainActor private static var builtIns: [OscillatorType: WaveTable] = [:]

    // The waveform at `phase`, in cycles from 0 up to 1, at `frequency`,
    // from the table with the most partials below `nyquist`.
    func sample(phase: Double, frequency: Float, nyquist: Float) -> Float {
        let table = tables[Self.tableIndex(frequency: abs(frequency), nyquist: nyquist)]
        let position = phase * Double(Self.size)
        let index = min(Int(position), Self.size - 1)
        let fraction = Float(position - Double(index))
        let next = table[(index + 1) & (Self.size - 1)]
        return table[index] + fraction * (next - table[index])
    }

    private static func tableIndex(frequency: Float, nyquist: Float) -> Int {
        partialCounts.firstIndex { Float($0) * frequency < nyquist } ?? partialCounts.count - 1
    }

    // x(n) = Σ a[k] cos(2πkn/N) + b[k] sin(2πkn/N) for k from 1 to `partials`:
    // the real part of the inverse transform of a[k] - i b[k].
    private static func synthesize(real: [Float], imag: [Float], partials: Int) -> [Float] {
        var spectrumReal = [Double](repeating: 0, count: size)
        var spectrumImag = [Double](repeating: 0, count: size)
        if partials >= 1 {
            for k in 1 ... partials {
                spectrumReal[k] = Double(real[k])
                spectrumImag[k] = -Double(imag[k])
            }
        }
        inverseFFT(real: &spectrumReal, imag: &spectrumImag)
        return spectrumReal.map { Float($0) }
    }

    // An unscaled inverse discrete Fourier transform, in place, of a
    // power-of-two length.
    private static func inverseFFT(real: inout [Double], imag: inout [Double]) {
        let count = real.count
        var j = 0
        for i in 1 ..< count {
            var bit = count >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j |= bit
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
        }
        var length = 2
        while length <= count {
            let angle = 2 * Double.pi / Double(length)
            for start in stride(from: 0, to: count, by: length) {
                for offset in 0 ..< length / 2 {
                    let twiddleReal = cos(angle * Double(offset))
                    let twiddleImag = sin(angle * Double(offset))
                    let even = start + offset
                    let odd = even + length / 2
                    let oddReal = real[odd] * twiddleReal - imag[odd] * twiddleImag
                    let oddImag = real[odd] * twiddleImag + imag[odd] * twiddleReal
                    real[odd] = real[even] - oddReal
                    imag[odd] = imag[even] - oddImag
                    real[even] += oddReal
                    imag[even] += oddImag
                }
            }
            length <<= 1
        }
    }
}
#endif
