#if os(Emscripten)
// The sources that a start and a stop time schedule. A started source keeps
// itself until it ends, then calls onended, as the context does natively.
@MainActor
public class AudioScheduledSourceNode: AudioNode {
    public var onended: (() -> Void)?

    public func start(_ when: Double = 0) throws {
        try object.call("start", nil, [when])
        keepUntilEnded()
    }

    public func stop(_ when: Double = 0) throws {
        try object.call("stop", nil, [when])
    }

    // Called once started. The listener holds the source until the ended
    // event, which the browser sends once.
    func keepUntilEnded() {
        object.setListener("ended", { source in
            MainActor.assumeIsolated {
                let source = Unmanaged<AudioScheduledSourceNode>.fromOpaque(source!).takeRetainedValue()
                source.object.setListener("ended", nil, nil)
                source.onended?()
            }
        }, Unmanaged.passRetained(self).toOpaque())
    }
}
#endif
