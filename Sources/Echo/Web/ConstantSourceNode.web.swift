#if os(Emscripten)
public final class ConstantSourceNode: AudioNode {
    public private(set) lazy var offset = AudioParam(context: context, object: object.object("offset")!)

    public init(context: BaseAudioContext) {
        // The browser throws only for invalid options, and none are passed.
        super.init(context: context, object: try! JSObjectReference.new("ConstantSourceNode", context: context.object))
    }

    public func start(_ when: Double = 0) throws {
        try object.call("start", nil, [when])
    }

    public func stop(_ when: Double = 0) throws {
        try object.call("stop", nil, [when])
    }
}
#endif
