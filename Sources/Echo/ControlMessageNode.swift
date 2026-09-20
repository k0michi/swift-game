import Atomics

final class ControlMessageNode: @unchecked Sendable {
    let message: ControlMessage?
    let next = ManagedAtomic<UnsafeMutableRawPointer?>(nil)

    init(message: ControlMessage?) {
        self.message = message
    }
}
