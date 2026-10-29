// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
public final class AudioDestinationNode: AudioNode {
    public let maxChannelCount: UInt32

    // Its settings are the context's, so that a new one has those an old
    // one was given.
    init(context: BaseAudioContext, numberOfChannels: UInt32) {
        maxChannelCount = numberOfChannels
        let settings = context.destinationSettings
        super.init(
            context: context,
            numberOfInputs: 1,
            numberOfOutputs: 1,
            channelCount: settings.channelCount,
            channelCountMode: settings.channelCountMode,
            channelInterpretation: settings.channelInterpretation
        )
    }

    public override func setChannelCount(_ channelCount: UInt32) throws {
        if context is OfflineAudioContext {
            guard channelCount == self.channelCount else { throw WebAudioError.invalidState }
        } else {
            guard (1 ... maxChannelCount).contains(channelCount) else { throw WebAudioError.indexSize }
            try super.setChannelCount(channelCount)
            context.destinationSettings.channelCount = channelCount
        }
    }

    public override func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        if context is OfflineAudioContext {
            guard channelCountMode == .explicit else { throw WebAudioError.invalidState }
        } else {
            try super.setChannelCountMode(channelCountMode)
            context.destinationSettings.channelCountMode = channelCountMode
        }
    }

    public override func setChannelInterpretation(_ channelInterpretation: ChannelInterpretation) {
        super.setChannelInterpretation(channelInterpretation)
        context.destinationSettings.channelInterpretation = channelInterpretation
    }
}
#endif
