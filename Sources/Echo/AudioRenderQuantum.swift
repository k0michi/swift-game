final class AudioRenderQuantum {
    let frameCount: Int
    let channelCapacity: Int

    private(set) var channelCount: Int
    private let samples: UnsafeMutableBufferPointer<Float>

    init(channelCapacity: Int, frameCount: Int, channelCount: Int? = nil) {
        let initialChannelCount = channelCount ?? channelCapacity

        precondition(channelCapacity > 0)
        precondition(frameCount > 0)
        precondition((0 ... channelCapacity).contains(initialChannelCount))

        self.frameCount = frameCount
        self.channelCapacity = channelCapacity
        self.channelCount = initialChannelCount
        samples = .allocate(capacity: channelCapacity * frameCount)
        samples.initialize(repeating: 0)
    }

    deinit {
        samples.deinitialize()
        samples.deallocate()
    }

    func setChannelCount(_ channelCount: Int) {
        precondition((0 ... channelCapacity).contains(channelCount))

        self.channelCount = channelCount
    }

    func channelData(_ channel: Int) -> UnsafeMutableBufferPointer<Float> {
        precondition((0 ..< channelCount).contains(channel))

        let start = samples.baseAddress.unsafelyUnwrapped + channel * frameCount
        return UnsafeMutableBufferPointer(start: start, count: frameCount)
    }

    func clear() {
        for channel in 0 ..< channelCount {
            channelData(channel).update(repeating: 0)
        }
    }

    func copy(from source: AudioRenderQuantum) {
        precondition(source.channelCount == channelCount)
        precondition(source.frameCount == frameCount)

        for channel in 0 ..< channelCount {
            _ = channelData(channel).update(from: source.channelData(channel))
        }
    }

    func sum(from source: AudioRenderQuantum) {
        precondition(source.channelCount == channelCount)
        precondition(source.frameCount == frameCount)

        for channel in 0 ..< channelCount {
            let sourceChannel = source.channelData(channel)
            let destinationChannel = channelData(channel)

            for frame in 0 ..< frameCount {
                destinationChannel[frame] += sourceChannel[frame]
            }
        }
    }
}
