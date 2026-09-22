import Atomics

final class RenderControlQueue: @unchecked Sendable {
    private final class Message {
        let plan: AudioRenderPlan?
        let next = ManagedAtomic<UnsafeMutableRawPointer?>(nil)

        init(plan: AudioRenderPlan?) {
            self.plan = plan
        }
    }

    let initialPlan: AudioRenderPlan

    private var producerTail: Message
    private var consumerHead: Message
    private var retainedMessages: [Message]
    private let appliedHead = ManagedAtomic<UnsafeMutableRawPointer?>(nil)

    @MainActor
    init(initialPlan: AudioRenderPlan) {
        self.initialPlan = initialPlan
        let sentinel = Message(plan: nil)
        producerTail = sentinel
        consumerHead = sentinel
        retainedMessages = [sentinel]
    }

    @MainActor
    func enqueue(_ plan: AudioRenderPlan) {
        reclaimAppliedPlans()
        let message = Message(plan: plan)
        retainedMessages.append(message)
        producerTail.next.store(Unmanaged.passUnretained(message).toOpaque(), ordering: .releasing)
        producerTail = message
    }

    func dequeue() -> AudioRenderPlan? {
        guard let pointer = consumerHead.next.load(ordering: .acquiring) else {
            return nil
        }
        let next = Unmanaged<Message>.fromOpaque(pointer).takeUnretainedValue()
        consumerHead = next
        return next.plan
    }

    func acknowledgeAppliedPlan() {
        appliedHead.store(Unmanaged.passUnretained(consumerHead).toOpaque(), ordering: .releasing)
    }

    @MainActor
    func reclaimAppliedPlans() {
        guard let pointer = appliedHead.load(ordering: .acquiring),
              let index = retainedMessages.firstIndex(where: {
                  Unmanaged.passUnretained($0).toOpaque() == pointer
              }), index > 0
        else { return }
        retainedMessages.removeFirst(index)
    }

    @MainActor
    var retainedMessageCount: Int { retainedMessages.count }
}
