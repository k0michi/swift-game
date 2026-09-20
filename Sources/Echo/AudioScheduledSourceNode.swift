open class AudioScheduledSourceNode: AudioNode {
    // TODO: Add onended after Echo has an event dispatch abstraction.
    private var hasStarted = false

    public func start(when: Double = 0) {
        precondition(!hasStarted, "An AudioScheduledSourceNode can only be started once")
        precondition(when >= 0, "when must be non-negative")
        hasStarted = true
        graph.startSource(id: id, when: when)
    }

    public func stop(when: Double = 0) {
        precondition(hasStarted, "An AudioScheduledSourceNode must be started before it can be stopped")
        precondition(when >= 0, "when must be non-negative")
        graph.stopSource(id: id, when: when)
    }
}
