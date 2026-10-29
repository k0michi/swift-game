// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// An oscillator's phase, which it keeps from one render quantum and render
// plan to the next, so that changing its type keeps it. Used only by the
// rendering thread.
final class OscillatorRenderState: @unchecked Sendable {
    // In cycles, from 0 up to 1.
    private var phase = 0.0
    private var hasStarted = false
    private var hasStopped = false

    // `frequency` gives the computedOscFrequency of each frame of the
    // quantum. Once stopped, later stop times have no effect.
    func render(
        into output: AudioRenderQuantum,
        frame: UInt64,
        sampleRate: Float,
        wave: WaveTable,
        startTime: Double?,
        stopTime: Double?,
        frequency: (Int) -> Float
    ) {
        let samples = output.channelData(0)
        let nyquist = sampleRate / 2
        for index in samples.indices {
            let time = Double(frame + UInt64(index)) / Double(sampleRate)
            // A stop time reached before the start time keeps the source
            // from playing.
            if !hasStopped, let stopTime, time >= stopTime {
                hasStopped = true
            }
            guard !hasStopped, let startTime, time >= startTime else {
                samples[index] = 0
                continue
            }
            let frequency = frequency(index)
            if !hasStarted {
                // The phase is 0 at the exact start time, between frames.
                hasStarted = true
                phase = Double(frequency) * (time - startTime)
                phase -= phase.rounded(.down)
            }
            samples[index] = wave.sample(phase: phase, frequency: frequency, nyquist: nyquist)
            phase += Double(frequency) / Double(sampleRate)
            phase -= phase.rounded(.down)
        }
    }
}
#endif
