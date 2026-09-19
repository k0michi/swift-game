public final class AudioContext: BaseAudioContext {
    public var baseLatency: Double { backend.baseLatency }
    public var outputLatency: Double { backend.outputLatency }

    public init(
        contextOptions: AudioContextOptions = AudioContextOptions(),
        backend: (any AudioBackend)? = nil
    ) {
        super.init(backend: backend ?? DefaultAudioBackend(options: contextOptions))
    }

    public func resume() async throws {
        try await backend.resume()
    }

    public func suspend() async throws {
        try await backend.suspend()
    }

    public func close() async throws {
        try await backend.close()
    }
}
