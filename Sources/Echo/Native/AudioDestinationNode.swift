// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// The context's output, which the context keeps for as long as it lives.
@MainActor
final class AudioDestinationHandler: AudioHandler {
    let maxChannelCount: UInt32

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

    override func setChannelCount(_ channelCount: UInt32) throws {
        if context is OfflineAudioContext {
            guard channelCount == self.channelCount else { throw WebAudioError.invalidState }
        } else {
            guard (1 ... maxChannelCount).contains(channelCount) else { throw WebAudioError.indexSize }
            try super.setChannelCount(channelCount)
        }
    }

    override func setChannelCountMode(_ channelCountMode: ChannelCountMode) throws {
        if context is OfflineAudioContext {
            guard channelCountMode == .explicit else { throw WebAudioError.invalidState }
        } else {
            try super.setChannelCountMode(channelCountMode)
        }
    }
}

// The node for the context's output. The context does not keep it, as it
// keeps the context; one the caller holds is the one it gets again.
@MainActor
public final class AudioDestinationNode: AudioNode {
    public var maxChannelCount: UInt32 { destinationHandler.maxChannelCount }

    var destinationHandler: AudioDestinationHandler {
        unsafeDowncast(handler, to: AudioDestinationHandler.self)
    }

    init(_ handler: AudioDestinationHandler) {
        super.init(handler: handler)
    }
}
#endif
