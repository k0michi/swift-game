public protocol AudioBackend: AnyObject {
    var sampleRate: Float { get }
    var currentTime: Double { get }
    var state: AudioContextState { get }
    var renderQuantumSize: UInt32 { get }
    var baseLatency: Double { get }
    var outputLatency: Double { get }

    func resume() async throws
    func suspend() async throws
    func close() async throws
}
