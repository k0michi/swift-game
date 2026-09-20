import Atomics

/// A lock-free multi-producer, single-consumer FIFO queue.
/// `consume(_:)` must only be called by the render thread.
final class ControlMessageQueue: @unchecked Sendable {
    private var head: UnsafeMutableRawPointer
    private let tail: ManagedAtomic<UnsafeMutableRawPointer>

    init() {
        let stub = Unmanaged.passRetained(ControlMessageNode(message: nil)).toOpaque()
        head = stub
        tail = ManagedAtomic(stub)
    }

    func enqueue(_ message: ControlMessage) {
        let pointer = Unmanaged.passRetained(ControlMessageNode(message: message)).toOpaque()
        let previous = tail.exchange(pointer, ordering: .acquiringAndReleasing)
        Unmanaged<ControlMessageNode>.fromOpaque(previous)
            .takeUnretainedValue().next.store(pointer, ordering: .releasing)
    }

    func consume(_ body: (ControlMessage) -> Void) {
        while let next = Unmanaged<ControlMessageNode>.fromOpaque(head)
            .takeUnretainedValue().next.load(ordering: .acquiring)
        {
            let previous = head
            head = next
            let node = Unmanaged<ControlMessageNode>.fromOpaque(next).takeUnretainedValue()
            if let message = node.message {
                body(message)
            }
            Unmanaged<ControlMessageNode>.fromOpaque(previous).release()
        }
    }

    deinit {
        consume { _ in }
        Unmanaged<ControlMessageNode>.fromOpaque(head).release()
    }
}
