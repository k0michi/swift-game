#if os(Emscripten)
public final class ConstantSourceNode: AudioScheduledSourceNode {
    public private(set) lazy var offset = AudioParam(context: context, object: object.object("offset")!)

    public init(context: BaseAudioContext) {
        // The browser throws only for invalid options, and none are passed.
        super.init(context: context, object: try! JSObjectReference.new("ConstantSourceNode", context: context.object))
    }
}
#endif
