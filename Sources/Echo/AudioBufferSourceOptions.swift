@MainActor
public struct AudioBufferSourceOptions {
    public var buffer: AudioBuffer?
    public var detune: Float
    public var loop: Bool
    public var loopEnd: Double
    public var loopStart: Double
    public var playbackRate: Float

    public init(
        buffer: AudioBuffer? = nil,
        detune: Float = 0,
        loop: Bool = false,
        loopEnd: Double = 0,
        loopStart: Double = 0,
        playbackRate: Float = 1
    ) {
        self.buffer = buffer
        self.detune = detune
        self.loop = loop
        self.loopEnd = loopEnd
        self.loopStart = loopStart
        self.playbackRate = playbackRate
    }

    // Throws what the options' own values make the constructor throw.
    func validate() throws {
        // The members are floats and doubles, which take only finite values.
        guard detune.isFinite, playbackRate.isFinite, loopEnd.isFinite, loopStart.isFinite else {
            throw WebAudioError.rangeError
        }
    }
}
