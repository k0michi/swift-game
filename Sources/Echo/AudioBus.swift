public struct AudioBus: Sendable {
    public let numberOfChannels: Int
    public let frameCapacity: Int
    private var samples: [Float]

    public init(numberOfChannels: Int, frameCapacity: Int) {
        precondition(numberOfChannels > 0)
        precondition(frameCapacity > 0)
        self.numberOfChannels = numberOfChannels
        self.frameCapacity = frameCapacity
        samples = Array(repeating: 0, count: numberOfChannels * frameCapacity)
    }

    public subscript(channel: Int, frame: Int) -> Float {
        get { samples[channel * frameCapacity + frame] }
        set { samples[channel * frameCapacity + frame] = newValue }
    }

    public mutating func clear(frameCount: Int) {
        precondition(frameCount >= 0 && frameCount <= frameCapacity)
        for channel in 0..<numberOfChannels {
            samples.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress?.advanced(by: channel * frameCapacity)
                    .update(repeating: 0, count: frameCount)
            }
        }
    }

    public func channelData(_ channel: Int, frameCount: Int) -> ArraySlice<Float> {
        precondition(channel >= 0 && channel < numberOfChannels)
        precondition(frameCount >= 0 && frameCount <= frameCapacity)
        let start = channel * frameCapacity
        return samples[start..<(start + frameCount)]
    }
}
