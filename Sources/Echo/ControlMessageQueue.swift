import Foundation

final class ControlMessageQueue {
    // TODO: Replace the render-side lock with an atomic, lock-free queue handoff before
    // consuming this queue from the SDL audio callback. Producers may coordinate, but
    // consume(_:) must never wait for the control thread.
    private let lock = NSLock()
    private var pending: [ControlMessage] = []
    private var rendering: [ControlMessage] = []

    init(capacity: Int = 64) {
        pending.reserveCapacity(capacity)
        rendering.reserveCapacity(capacity)
    }

    func enqueue(_ message: ControlMessage) {
        lock.withLock { pending.append(message) }
    }

    func consume(_ body: (ControlMessage) -> Void) {
        lock.withLock { swap(&pending, &rendering) }
        for message in rendering { body(message) }
        rendering.removeAll(keepingCapacity: true)
    }
}
