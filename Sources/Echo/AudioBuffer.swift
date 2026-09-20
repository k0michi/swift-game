public final class AudioBuffer {
    public static let minimumSampleRate: Float = 3_000
    public static let maximumSampleRate: Float = 768_000
    public static let maximumNumberOfChannels: UInt32 = 32

    public let sampleRate: Float
    public let length: UInt32
    public let numberOfChannels: UInt32

    public var duration: Double {
        Double(length) / Double(sampleRate)
    }

    private let channels: [UnsafeMutableBufferPointer<Float>]

    public init(options: AudioBufferOptions) throws {
        guard (1 ... Self.maximumNumberOfChannels).contains(options.numberOfChannels),
              options.length > 0,
              options.sampleRate.isFinite,
              (Self.minimumSampleRate ... Self.maximumSampleRate).contains(options.sampleRate)
        else {
            throw WebAudioError.notSupported
        }

        sampleRate = options.sampleRate
        length = options.length
        numberOfChannels = options.numberOfChannels
        channels = (0 ..< options.numberOfChannels).map { _ in
            let channel = UnsafeMutableBufferPointer<Float>.allocate(capacity: Int(options.length))
            channel.initialize(repeating: 0)
            return channel
        }
    }

    deinit {
        for channel in channels {
            channel.deinitialize()
            channel.deallocate()
        }
    }

    /// The returned pointer is valid only while this `AudioBuffer` remains alive.
    public func getChannelData(_ channel: UInt32) throws -> UnsafeMutableBufferPointer<Float> {
        guard channel < numberOfChannels else {
            throw WebAudioError.indexSize
        }

        return channels[Int(channel)]
    }

    public func copyFromChannel(
        _ destination: inout [Float],
        channelNumber: UInt32,
        bufferOffset: UInt32 = 0
    ) throws {
        let channel = try getChannelData(channelNumber)
        let frameCount = min(
            destination.count,
            max(0, channel.count - Int(bufferOffset))
        )

        for frame in 0 ..< frameCount {
            destination[frame] = channel[Int(bufferOffset) + frame]
        }
    }

    public func copyToChannel(
        _ source: [Float],
        channelNumber: UInt32,
        bufferOffset: UInt32 = 0
    ) throws {
        let channel = try getChannelData(channelNumber)
        let frameCount = min(
            source.count,
            max(0, channel.count - Int(bufferOffset))
        )

        for frame in 0 ..< frameCount {
            channel[Int(bufferOffset) + frame] = source[frame]
        }
    }
}
