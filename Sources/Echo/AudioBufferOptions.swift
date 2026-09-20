public struct AudioBufferOptions: Sendable, Equatable {
    public var numberOfChannels: UInt32
    public var length: UInt32
    public var sampleRate: Float

    public init(
        numberOfChannels: UInt32 = 1,
        length: UInt32,
        sampleRate: Float
    ) {
        self.numberOfChannels = numberOfChannels
        self.length = length
        self.sampleRate = sampleRate
    }
}
