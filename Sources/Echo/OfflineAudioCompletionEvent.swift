@MainActor
public struct OfflineAudioCompletionEvent {
    public let renderedBuffer: AudioBuffer

    public init(renderedBuffer: AudioBuffer) {
        self.renderedBuffer = renderedBuffer
    }
}
