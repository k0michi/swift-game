public enum AudioBufferError: Error, Equatable {
    case invalidChannelCount
    case invalidLength
    case invalidSampleRate
    case invalidChannel(UInt32)
}
