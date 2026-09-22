public protocol AudioOutputBackend: AnyObject, Sendable {
    var sampleRate: Float { get }
    var channelCount: UInt32 { get }

    // Render callbacks must be serialized, and start() must not leave one active if it throws.
    func start(
        render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void,
        onError: @escaping @Sendable () -> Void
    ) throws
    // stop() must return only after every in-flight render callback has finished.
    func stop() throws
}
