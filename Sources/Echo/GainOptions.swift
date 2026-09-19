public struct GainOptions: Sendable {
    public var audioNodeOptions: AudioNodeOptions
    public var gain: Float

    public init(audioNodeOptions: AudioNodeOptions = AudioNodeOptions(), gain: Float = 1) {
        self.audioNodeOptions = audioNodeOptions
        self.gain = gain
    }
}
