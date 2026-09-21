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
        guard channelCount == self.channelCount else {
            throw WebAudioError.notSupported
        }
    }

}
