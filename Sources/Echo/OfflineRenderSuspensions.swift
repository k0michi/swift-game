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
    let reached = DispatchSemaphore(value: 0)
    let resumed = DispatchSemaphore(value: 0)
    let state = ManagedAtomic<Int>(Status.scheduled)

    init(frame: UInt64) {
        self.frame = frame
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
            suspension.reached.signal()
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
                suspension.reached.signal()
                suspension.resumed.wait()
                if cancelled.load(ordering: .acquiring) { throw WebAudioError.invalidState }
                suspension.state.store(OfflineRenderSuspension.Status.resumed, ordering: .releasing)
            }
            pointer = suspension.next.load(ordering: .acquiring)
        }
    }
}
