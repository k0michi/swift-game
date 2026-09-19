import Foundation

final class DefaultAudioBackend: AudioBackend {
    let sampleRate: Float
    let renderQuantumSize: UInt32
    let baseLatency = 0.0
    let outputLatency = 0.0

    private let lock = NSLock()
    private var storedState = AudioContextState.suspended
    private var accumulatedTime = 0.0
    private var startedAt: TimeInterval?

    init(options: AudioContextOptions) {
        sampleRate = options.sampleRate ?? 48_000
        renderQuantumSize = switch options.renderSizeHint {
        case .default, .hardware: 128
        case .frames(let frames): frames
        }
    }

    var state: AudioContextState {
        lock.withLock { storedState }
    }

    var currentTime: Double {
        lock.withLock {
            guard let startedAt else { return accumulatedTime }
            return accumulatedTime + Date.timeIntervalSinceReferenceDate - startedAt
        }
    }

    func resume() async throws {
        lock.withLock {
            guard storedState != .closed, storedState != .running else { return }
            startedAt = Date.timeIntervalSinceReferenceDate
            storedState = .running
        }
    }

    func suspend() async throws {
        lock.withLock {
            guard storedState == .running else { return }
            if let startedAt {
                accumulatedTime += Date.timeIntervalSinceReferenceDate - startedAt
            }
            startedAt = nil
            storedState = .suspended
        }
    }

    func close() async throws {
        try await suspend()
        lock.withLock { storedState = .closed }
    }
}
