@MainActor
public final class MediaDevices {
    public var ondevicechange: (() -> Void)?

    private let backend: any MediaCaptureBackend

    public init(backend: any MediaCaptureBackend) {
        self.backend = backend
    }

    public func enumerateDevices() async throws -> [MediaDeviceInfo] {
        try await backend.enumerateDevices()
    }

    public func getUserMedia(
        _ constraints: MediaStreamConstraints = MediaStreamConstraints()
    ) async throws -> MediaStream {
        guard constraints.audio.requested || constraints.video.requested else {
            throw WebAudioError.notSupported
        }
        return try await backend.getUserMedia(constraints)
    }

    // TODO: Add getSupportedConstraints and devicechange dispatch when backend support exists.
}
