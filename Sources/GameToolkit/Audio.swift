import Echo
import RealModule

extension BaseAudioContext {
    /// A gain that rises linearly from silence to `peak` over `attack`
    /// seconds from `start`, then falls exponentially to nearly silence at
    /// `decayEnd` seconds.
    public func createEnvelope(at start: Double, attack: Double = 0, peak: Float, decayEnd: Double) throws -> GainNode {
        let gain = createGain()
        if attack > 0 {
            try gain.gain.setValueAtTime(0, startTime: start)
                .linearRampToValueAtTime(peak, endTime: start + attack)
        } else {
            try gain.gain.setValueAtTime(peak, startTime: start)
        }
        try gain.gain.exponentialRampToValueAtTime(0.001, endTime: start + decayEnd)
        return gain
    }

    /// `seconds` of mono white noise, from -1 to 1, from a xorshift generator.
    public func createNoiseBuffer(seconds: Float = 1) throws -> AudioBuffer {
        let buffer = try createBuffer(
            numberOfChannels: 1, length: UInt32(seconds * sampleRate), sampleRate: sampleRate)
        var state: UInt32 = 0x1234_5678
        let samples = try buffer.getChannelData(0)
        for index in samples.indices {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            samples[index] = Float(Double(state) / Double(UInt32.max) * 2 - 1)
        }
        return buffer
    }

    /// A master volume of `volume` into the destination, with soft clipping,
    /// tanh(4 volume x), so that several sounds at once do not clip harshly.
    /// Sounds connect to the gain it returns.
    public func createSoftClippedOutput(volume: Float = 0.1) throws -> GainNode {
        // The volume scales the signal into the curve's input range, so the
        // curve gives tanh(4 volume x) for x up to 1 / volume.
        let gain = createGain()
        gain.gain.value = volume
        let clipper = createWaveShaper()
        let curveSize = 1025
        try clipper.setCurve((0..<curveSize).map { index in
            Float(Double.tanh(4 * (Double(index) / Double(curveSize - 1) * 2 - 1)))
        })
        try gain.connect(clipper).connect(destination)
        return gain
    }
}

extension AudioContext {
    /// Resumes the context if it is suspended, without waiting. A browser
    /// lets it start only after the page gets a user gesture, so games call
    /// this for every click and key press there.
    public func resumeIfSuspended() {
        guard state == .suspended else { return }
        Task {
            do {
                try await resume()
            } catch {
                print("Could not start sound: \(error)")
            }
        }
    }
}
