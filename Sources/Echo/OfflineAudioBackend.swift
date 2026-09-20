import Foundation

final class OfflineAudioBackend: AudioBackend {
    let sampleRate: Float
    let renderQuantumSize: UInt32
    let baseLatency = 0.0
    let outputLatency = 0.0
    var currentTime: Double { 0 }

    private let lock = NSLock()
    private var storedState = AudioContextState.suspended

    init(sampleRate: Float, renderQuantumSize: UInt32) {
        self.sampleRate = sampleRate
        self.renderQuantumSize = renderQuantumSize
    }

    var state: AudioContextState {
        lock.withLock { storedState }
    }

    func resume() async throws {
        setState(.running)
    }

    func suspend() async throws {
        setState(.suspended)
    }

    func close() async throws {
        setState(.closed)
    }

    func setState(_ state: AudioContextState) {
        lock.withLock { storedState = state }
    }
}
