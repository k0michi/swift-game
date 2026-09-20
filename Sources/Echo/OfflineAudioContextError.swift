public enum OfflineAudioContextError: Error, Equatable {
    case invalidChannelCount
    case invalidLength
    case invalidSampleRate
    case invalidRenderQuantumSize
    case renderingComplete
    case contextClosed
}
