public final class AudioDestinationNode: AudioNode {
    public let maxChannelCount: UInt32

    init(context: BaseAudioContext, maxChannelCount: UInt32 = 2) {
        self.maxChannelCount = maxChannelCount
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 0,
            options: AudioNodeOptions(channelCount: maxChannelCount, channelCountMode: .explicit)
        )
    }
}
