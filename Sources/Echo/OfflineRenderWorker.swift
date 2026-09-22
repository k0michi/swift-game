import Atomics
import Foundation

// Ownership moves to the worker for the duration of one render job; callers must not
// access the buffer until the returned result is received.
struct OfflineRenderBuffer: @unchecked Sendable {
    let value: AudioBuffer
}

struct OfflineRenderResult: @unchecked Sendable {
    let buffer: AudioBuffer
    let ranOnMainThread: Bool
}

final class OfflineRenderWorker: @unchecked Sendable {
    private let controlQueue: RenderControlQueue
    private let buffer: AudioBuffer
    private let target: OfflineRenderTarget
    private let initialFrame: UInt64
    private let currentFrame: ManagedAtomic<UInt64>
    private let cancelled: ManagedAtomic<Bool>
    private let suspensions: OfflineRenderSuspensions?
    private let beforeQuantum: (@Sendable (UInt64) -> Void)?
    private let continuation: CheckedContinuation<OfflineRenderResult, Error>

    private init(
        controlQueue: RenderControlQueue,
        buffer: OfflineRenderBuffer,
        target: OfflineRenderTarget,
        initialFrame: UInt64,
        currentFrame: ManagedAtomic<UInt64>,
        cancelled: ManagedAtomic<Bool>,
        suspensions: OfflineRenderSuspensions?,
        beforeQuantum: (@Sendable (UInt64) -> Void)?,
        continuation: CheckedContinuation<OfflineRenderResult, Error>
    ) {
        self.controlQueue = controlQueue
        self.buffer = buffer.value
        self.target = target
        self.initialFrame = initialFrame
        self.currentFrame = currentFrame
        self.cancelled = cancelled
        self.suspensions = suspensions
        self.beforeQuantum = beforeQuantum
        self.continuation = continuation
    }

    static func render(
        controlQueue: RenderControlQueue,
        into buffer: OfflineRenderBuffer,
        from initialFrame: UInt64,
        currentFrame: ManagedAtomic<UInt64>,
        cancelled: ManagedAtomic<Bool> = ManagedAtomic(false),
        suspensions: OfflineRenderSuspensions? = nil,
        beforeQuantum: (@Sendable (UInt64) -> Void)? = nil
    ) async throws -> OfflineRenderResult {
        let target = try OfflineRenderTarget(buffer: buffer.value, plan: controlQueue.initialPlan)
        return try await withCheckedThrowingContinuation { continuation in
            let worker = OfflineRenderWorker(
                controlQueue: controlQueue,
                buffer: buffer,
                target: target,
                initialFrame: initialFrame,
                currentFrame: currentFrame,
                cancelled: cancelled,
                suspensions: suspensions,
                beforeQuantum: beforeQuantum,
                continuation: continuation
            )
            Thread { worker.run() }.start()
        }
    }

    private func run() {
        do {
            var plan = controlQueue.initialPlan
            let quantum = plan.frameCount
            for offset in stride(from: 0, to: Int(buffer.length), by: quantum) {
                if cancelled.load(ordering: .acquiring) { throw WebAudioError.invalidState }
                let frame = initialFrame + UInt64(offset)
                beforeQuantum?(frame)
                try suspensions?.waitIfScheduled(at: frame, cancelled: cancelled)
                if cancelled.load(ordering: .acquiring) { throw WebAudioError.invalidState }
                while let replacement = controlQueue.dequeue() {
                    guard replacement.frameCount == quantum,
                          replacement.destinationChannelCount == target.channelCount
                    else { throw WebAudioError.notSupported }
                    plan = replacement
                }
                controlQueue.acknowledgeAppliedPlan()
                plan.render(at: frame, into: target, offset: offset)
                currentFrame.store(frame + UInt64(quantum), ordering: .releasing)
            }
            continuation.resume(returning: OfflineRenderResult(
                buffer: buffer,
                ranOnMainThread: Thread.isMainThread
            ))
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
