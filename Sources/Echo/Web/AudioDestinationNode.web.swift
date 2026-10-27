#if os(Emscripten)
public final class AudioDestinationNode: AudioNode {
    public let maxChannelCount: UInt32

    override init(context: BaseAudioContext, object: JSObjectReference) {
        maxChannelCount = UInt32(object.number("maxChannelCount"))
        super.init(context: context, object: object)
    }
}
#endif
