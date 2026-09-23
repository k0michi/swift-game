@MainActor
public protocol MediaCaptureBackend: AnyObject {
    func enumerateDevices() async throws -> [MediaDeviceInfo]
    func getUserMedia(_ constraints: MediaStreamConstraints) async throws -> MediaStream
}
