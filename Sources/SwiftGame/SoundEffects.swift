import Echo
import GameToolkit
import SDL3

/// Sound effects synthesized with Web Audio nodes, through Echo, which hands
/// them to the browser's Web Audio on the web; the game uses no audio files.
/// Each sound is oscillators or noise with exponential ramps, a stereo
/// panner and a low-pass filter, which the context lets go of once played.
@MainActor
final class SoundEffects {
    private let context: AudioContext
    /// Where every sound goes.
    private let master: AudioNode
    /// A second of white noise, which noise sources play from.
    private let noise: AudioBuffer
    private var lastBounceTime = -Double.infinity

    init(system: System) throws {
        context = try makeAudioContext(system: system)
        master = try context.createSoftClippedOutput()
        noise = try context.createNoiseBuffer()
        context.resumeIfSuspended()
    }

    /// Starts the sound if it is not playing, as a browser lets it only after
    /// a user gesture.
    func resume() {
        context.resumeIfSuspended()
    }

    /// A short blip for two bullets colliding. `speed` is how fast they
    /// approached (points per second) and `x` where they met.
    func bounce(speed: Float, x: Float, fieldWidth: Float) {
        play { now in
            // At most one blip every 40 ms, so a pile-up stays readable.
            guard now - lastBounceTime >= 0.04 else { return }
            lastBounceTime = now
            let oscillator = context.createOscillator()
            oscillator.frequency.value = 500 + min(speed, 600)
            let panner = context.createStereoPanner()
            panner.pan.value = max(-1, min(1, x / fieldWidth * 2 - 1))
            try oscillator.connect(context.createEnvelope(at: now, attack: 0.005, peak: 0.25, decayEnd: 0.08))
                .connect(panner).connect(master)
            try oscillator.start(now)
            try oscillator.stop(now + 0.1)
        }
    }

    /// A noise crash with a falling tone, for being hit.
    func gameOver() {
        play { now in
            let crash = context.createBufferSource()
            try crash.setBuffer(noise)
            let filter = context.createBiquadFilter()
            filter.type = .lowpass
            try filter.frequency.setValueAtTime(3000, startTime: now)
                .exponentialRampToValueAtTime(80, endTime: now + 0.5)
            try crash.connect(filter).connect(context.createEnvelope(at: now, peak: 0.8, decayEnd: 0.5)).connect(master)
            try crash.start(now)
            try crash.stop(now + 0.5)

            let tone = context.createOscillator()
            try tone.setType(.sawtooth)
            try tone.frequency.setValueAtTime(220, startTime: now)
                .exponentialRampToValueAtTime(40, endTime: now + 0.6)
            try tone.connect(context.createEnvelope(at: now, peak: 0.3, decayEnd: 0.6)).connect(master)
            try tone.start(now)
            try tone.stop(now + 0.65)
        }
    }

    /// Two rising notes for a new round.
    func restart() {
        play { now in
            for (index, frequency) in [523.25, 783.99].enumerated() {
                let start = now + Double(index) * 0.08
                let note = context.createOscillator()
                try note.setType(.square)
                note.frequency.value = Float(frequency)
                try note.connect(context.createEnvelope(at: start, peak: 0.12, decayEnd: 0.12)).connect(master)
                try note.start(start)
                try note.stop(start + 0.13)
            }
        }
    }

    /// Makes the sounds that `schedule` makes for the context's current
    /// time, if the context is playing. While it is not, as in a browser
    /// before the page gets a user gesture, time stands still, so sounds
    /// scheduled then would all play at once when it starts.
    private func play(_ schedule: (Double) throws -> Void) {
        guard context.state == .running else { return }
        do {
            try schedule(context.currentTime)
        } catch {
            print("Could not play a sound: \(error)")
        }
    }
}
