// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Atomics
import Foundation

final class OfflineRenderSuspension: @unchecked Sendable {
    enum Status {
        static let scheduled = 0
        static let reached = 1
        static let resumed = 2
        static let cancelled = 3
    }

    let frame: UInt64
    let next = ManagedAtomic<UnsafeMutableRawPointer?>(nil)
    let resumed = DispatchSemaphore(value: 0)
    let state = ManagedAtomic<Int>(Status.scheduled)

    // Whether rendering reached the suspension, or it was cancelled, and who
    // waits for that. Waiting holds no thread, as many suspensions may wait
    // at once, more than a thread pool has threads.
    private let lock = NSLock()
    private var isReached = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(frame: UInt64) {
        self.frame = frame
    }

    func signalReached() {
        lock.lock()
        isReached = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    func waitUntilReached() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isReached {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}

final class OfflineRenderSuspensions: @unchecked Sendable {
    private let head = OfflineRenderSuspension(frame: 0)
    private var tail: OfflineRenderSuspension
    private var retained: [OfflineRenderSuspension]

    @MainActor
    init() {
        tail = head
        retained = [head]
    }

    @MainActor
    func schedule(at frame: UInt64) -> OfflineRenderSuspension {
        let suspension = OfflineRenderSuspension(frame: frame)
        retained.append(suspension)
        tail.next.store(Unmanaged.passUnretained(suspension).toOpaque(), ordering: .releasing)
        tail = suspension
        return suspension
    }

    @MainActor
    func contains(frame: UInt64) -> Bool {
        retained.dropFirst().contains { $0.frame == frame }
    }

    @MainActor
    func cancelAll() {
        for suspension in retained.dropFirst() {
            suspension.state.store(OfflineRenderSuspension.Status.cancelled, ordering: .releasing)
            suspension.signalReached()
            suspension.resumed.signal()
        }
    }

    func waitIfScheduled(at frame: UInt64, cancelled: ManagedAtomic<Bool>) throws {
        var pointer = head.next.load(ordering: .acquiring)
        while let current = pointer {
            let suspension = Unmanaged<OfflineRenderSuspension>.fromOpaque(current).takeUnretainedValue()
            if suspension.frame <= frame,
               suspension.state.compareExchange(
                   expected: OfflineRenderSuspension.Status.scheduled,
                   desired: OfflineRenderSuspension.Status.reached,
                   ordering: .acquiringAndReleasing
               ).exchanged {
                suspension.signalReached()
                suspension.resumed.wait()
                if cancelled.load(ordering: .acquiring) { throw WebAudioError.invalidState }
                suspension.state.store(OfflineRenderSuspension.Status.resumed, ordering: .releasing)
            }
            pointer = suspension.next.load(ordering: .acquiring)
        }
    }
}
#endif
