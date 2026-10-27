// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
public struct MediaStreamAudioSourceOptions {
    public let mediaStream: MediaStream

    public init(mediaStream: MediaStream) {
        self.mediaStream = mediaStream
    }
}
#endif
