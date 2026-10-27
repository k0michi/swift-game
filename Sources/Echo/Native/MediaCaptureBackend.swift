// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
public protocol MediaCaptureBackend: AnyObject {
    func enumerateDevices() async throws -> [MediaDeviceInfo]
    func getUserMedia(_ constraints: MediaStreamConstraints) async throws -> MediaStream
}
#endif
