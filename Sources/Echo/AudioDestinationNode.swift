public final class AudioDestinationNode: AudioNode {
    public let maxChannelCount: UInt32

    init(context: BaseAudioContext, numberOfChannels: UInt32) {
        maxChannelCount = numberOfChannels
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: numberOfChannels,
            channelCountMode: .explicit,
            channelInterpretation: .speakers
        )
    }

    public override func setChannelCount(_ channelCount: UInt32) throws {
        if context is OfflineAudioContext {
            guard channelCount == self.channelCount else { throw WebAudioError.invalidState }
        } else {
            guard (1 ... maxChannelCount).contains(channelCount) else { throw WebAudioError.indexSize }
            try super.setChannelCount(channelCount)
        }
    }

    public override func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        if context is OfflineAudioContext {
            guard channelCountMode == .explicit else { throw WebAudioError.invalidState }
        } else {
            try super.setChannelCountMode(channelCountMode)
        }
    }
}
