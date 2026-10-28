import Foundation
import SDL3

/// Sound effects synthesized into an SDL audio stream; the game uses no audio
/// files. The sounds are those of the Web Audio version: oscillators and
/// noise with exponential ramps, a stereo panner and a low-pass filter.
@MainActor
final class SoundEffects {
    private static let sampleRate = 48_000

    private let stream: AudioStream
    private let synth: Synth
    private var lastBounceTime = -Double.infinity

    init() throws {
        let synth = Synth(sampleRate: Double(Self.sampleRate))
        self.synth = synth
        stream = try openAudioDeviceStream(
            devid: audioDeviceDefaultPlayback,
            spec: AudioSpec(format: .f32, channels: 2, freq: Int32(Self.sampleRate))
        ) { stream, additionalAmount, _ in
            guard additionalAmount > 0 else { return }
            // SDL holds the stream's lock while it calls back.
            let samples = synth.render(frameCount: Int(additionalAmount + 7) / 8)
            try? samples.withUnsafeBytes {
                try putAudioStreamData(stream: stream, buf: $0)
            }
        }
        try resumeAudioStreamDevice(stream: stream)
    }

    /// A short blip for two bullets colliding. `speed` is how fast they
    /// approached (points per second) and `x` where they met.
    func bounce(speed: Float, x: Float, fieldWidth: Float) {
        play { now in
            // At most one blip every 40 ms, so a pile-up stays readable.
            guard now - lastBounceTime >= 0.04 else { return [] }
            lastBounceTime = now
            return [
                Voice(
                    start: now, stop: now + 0.1,
                    source: .oscillator(.sine),
                    frequency: Ramp(Double(500 + min(speed, 600))),
                    gain: Envelope(attack: 0.005, peak: 0.25, decayEnd: 0.08),
                    pan: Double(max(-1, min(1, x / fieldWidth * 2 - 1))))
            ]
        }
    }

    /// A noise crash with a falling tone, for being hit.
    func gameOver() {
        play { now in
            [
                Voice(
                    start: now, stop: now + 0.5,
                    source: .noise,
                    gain: Envelope(peak: 0.8, decayEnd: 0.5),
                    lowpass: Ramp(from: 3000, to: 80, over: 0.5)),
                Voice(
                    start: now, stop: now + 0.65,
                    source: .oscillator(.sawtooth),
                    frequency: Ramp(from: 220, to: 40, over: 0.6),
                    gain: Envelope(peak: 0.3, decayEnd: 0.6)),
            ]
        }
    }

    /// Two rising notes for a new round.
    func restart() {
        play { now in
            [523.25, 783.99].enumerated().map { index, frequency in
                let start = now + Double(index) * 0.08
                return Voice(
                    start: start, stop: start + 0.13,
                    source: .oscillator(.square),
                    frequency: Ramp(frequency),
                    gain: Envelope(peak: 0.12, decayEnd: 0.12))
            }
        }
    }

    /// Adds the voices that `schedule` makes for the synthesizer's current
    /// time, if the device is playing. While it is not, as in a browser before
    /// the page gets a user gesture, time stands still, so sounds scheduled
    /// then would all play at once when it starts.
    private func play(_ schedule: (Double) -> [Voice]) {
        do {
            try lockAudioStream(stream: stream)
            defer { try? unlockAudioStream(stream: stream) }
            guard synth.isPlaying else { return }
            synth.voices += schedule(synth.time)
        } catch {
            print("Could not play a sound: \(error)")
        }
    }
}

/// A value that ramps exponentially, as AudioParam's
/// exponentialRampToValueAtTime does.
private struct Ramp {
    var from, to, duration: Double

    init(_ value: Double) {
        self.init(from: value, to: value, over: 1)
    }

    init(from: Double, to: Double, over duration: Double) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    func value(at time: Double) -> Double {
        from * pow(to / from, min(max(time / duration, 0), 1))
    }
}

/// A gain that rises linearly to `peak` over `attack` seconds, then falls
/// exponentially to nearly silence at `decayEnd`.
private struct Envelope {
    var attack: Double = 0
    var peak: Double
    var decayEnd: Double

    func value(at time: Double) -> Double {
        if time < attack {
            return peak * time / attack
        }
        return Ramp(from: peak, to: 0.001, over: decayEnd - attack).value(at: time - attack)
    }
}

private enum Waveform {
    case sine, square, sawtooth
}

private enum Source {
    case oscillator(Waveform)
    case noise
}

private struct Voice {
    var start, stop: Double
    var source: Source
    var frequency = Ramp(440)
    var gain: Envelope
    // A one-pole low-pass filter's cutoff, in hertz.
    var lowpass: Ramp?
    // Mono voices play in both channels at full gain, and panned ones with
    // equal power, as Web Audio's StereoPannerNode does.
    var pan: Double?

    var phase = 0.0
    var filtered = 0.0
}

/// Mixes the voices. Only touched with the audio stream locked.
private final class Synth: @unchecked Sendable {
    let sampleRate: Double
    var voices: [Voice] = []
    /// Seconds of audio rendered so far.
    private(set) var time = 0.0
    private var lastRender: ContinuousClock.Instant?
    private var noiseState: UInt32 = 0x1234_5678

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Whether the device has asked for audio recently.
    var isPlaying: Bool {
        guard let lastRender else { return false }
        return ContinuousClock.now - lastRender < .milliseconds(250)
    }

    /// Interleaved stereo samples for the next `frameCount` frames.
    func render(frameCount: Int) -> [Float] {
        lastRender = .now
        var samples = [Float](repeating: 0, count: frameCount * 2)
        for index in voices.indices {
            render(voice: &voices[index], into: &samples)
        }
        time += Double(frameCount) / sampleRate
        voices.removeAll { $0.stop <= time }
        // The master volume, with soft clipping so that several sounds at once
        // do not clip harshly.
        for index in samples.indices {
            samples[index] = Float(tanh(Double(samples[index]) * 0.4))
        }
        return samples
    }

    private func render(voice: inout Voice, into samples: inout [Float]) {
        let (left, right): (Double, Double) =
            if let pan = voice.pan {
                (cos((pan + 1) * .pi / 4), sin((pan + 1) * .pi / 4))
            } else {
                (1, 1)
            }
        for frame in 0..<(samples.count / 2) {
            let now = time + Double(frame) / sampleRate
            guard now >= voice.start, now < voice.stop else { continue }
            let elapsed = now - voice.start
            var sample: Double
            switch voice.source {
            case .oscillator(let waveform):
                sample =
                    switch waveform {
                    case .sine: sin(2 * .pi * voice.phase)
                    case .square: voice.phase < 0.5 ? 1 : -1
                    case .sawtooth: 2 * voice.phase - 1
                    }
                voice.phase += voice.frequency.value(at: elapsed) / sampleRate
                voice.phase -= voice.phase.rounded(.down)
            case .noise:
                sample = nextNoise()
            }
            if let lowpass = voice.lowpass {
                let alpha = 1 - exp(-2 * .pi * lowpass.value(at: elapsed) / sampleRate)
                voice.filtered += alpha * (sample - voice.filtered)
                sample = voice.filtered
            }
            sample *= voice.gain.value(at: elapsed)
            samples[frame * 2] += Float(sample * left)
            samples[frame * 2 + 1] += Float(sample * right)
        }
    }

    // White noise from -1 to 1, from a xorshift generator, which is cheap
    // enough for the audio thread.
    private func nextNoise() -> Double {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Double(noiseState) / Double(UInt32.max) * 2 - 1
    }
}
