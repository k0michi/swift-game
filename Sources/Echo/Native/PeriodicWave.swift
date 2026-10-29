// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
public final class PeriodicWave {
    public let context: BaseAudioContext
    let waveTable: WaveTable

    public init(context: BaseAudioContext, options: PeriodicWaveOptions = PeriodicWaveOptions()) throws {
        let (real, imag) = try options.coefficients()
        self.context = context
        waveTable = WaveTable(real: real, imag: imag, normalize: !options.disableNormalization)
    }
}
#endif
