public final class AudioBuffer {
    public let sampleRate: Float
    public let length: UInt32
    public var duration: Double { Double(length) / Double(sampleRate) }
    public let numberOfChannels: UInt32

    private var channels: [[Float]]

    public init(options: AudioBufferOptions) throws {
        guard options.numberOfChannels > 0 else { throw AudioBufferError.invalidChannelCount }
        guard options.length > 0 else { throw AudioBufferError.invalidLength }
        guard options.sampleRate > 0, options.sampleRate.isFinite else { throw AudioBufferError.invalidSampleRate }
        sampleRate = options.sampleRate
        length = options.length
        numberOfChannels = options.numberOfChannels
        channels = Array(
            repeating: Array(repeating: 0, count: Int(options.length)),
            count: Int(options.numberOfChannels)
        )
    }

    public func getChannelData(_ channel: UInt32) throws -> [Float] {
        guard channel < numberOfChannels else { throw AudioBufferError.invalidChannel(channel) }
        return channels[Int(channel)]
    }

    public func copyFromChannel(
        to destination: inout [Float],
        channelNumber: UInt32,
        bufferOffset: UInt32 = 0
    ) throws {
        guard channelNumber < numberOfChannels else { throw AudioBufferError.invalidChannel(channelNumber) }
        let source = channels[Int(channelNumber)].dropFirst(Int(bufferOffset))
        for index in destination.indices.prefix(source.count) {
            destination[index] = source[source.index(source.startIndex, offsetBy: index)]
        }
    }

    public func copyToChannel(
        from source: [Float],
        channelNumber: UInt32,
        bufferOffset: UInt32 = 0
    ) throws {
        guard channelNumber < numberOfChannels else { throw AudioBufferError.invalidChannel(channelNumber) }
        let offset = Int(bufferOffset)
        guard offset < channels[Int(channelNumber)].count else { return }
        let count = min(source.count, channels[Int(channelNumber)].count - offset)
        channels[Int(channelNumber)].replaceSubrange(offset..<(offset + count), with: source.prefix(count))
    }
}
