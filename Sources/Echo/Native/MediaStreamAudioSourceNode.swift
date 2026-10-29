// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
@MainActor
final class MediaStreamAudioSourceHandler: AudioHandler {
    let mediaStream: MediaStream
    let renderState: MediaStreamRenderState

    init(context: AudioContext, options: MediaStreamAudioSourceOptions) throws {
        guard let track = options.mediaStream.getAudioTracks().min(by: {
            $0.id.utf16.lexicographicallyPrecedes($1.id.utf16)
        }) else {
            throw WebAudioError.invalidState
        }
        mediaStream = options.mediaStream
        renderState = MediaStreamRenderState(track: track, sampleRate: context.sampleRate)
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 1,
            channelCount: 2,
            channelCountMode: .max,
            channelInterpretation: .speakers
        )
    }

    // It plays while its track is live, whoever keeps it.
    override var playsOnItsOwn: Bool { !renderState.track.ended }
}

@MainActor
public final class MediaStreamAudioSourceNode: AudioNode {
    public var mediaStream: MediaStream { mediaHandler.mediaStream }

    var mediaHandler: MediaStreamAudioSourceHandler {
        unsafeDowncast(handler, to: MediaStreamAudioSourceHandler.self)
    }

    var renderState: MediaStreamRenderState { mediaHandler.renderState }

    public init(context: AudioContext, options: MediaStreamAudioSourceOptions) throws {
        super.init(handler: try MediaStreamAudioSourceHandler(context: context, options: options))
    }
}

final class MediaStreamRenderState: @unchecked Sendable {
    let track: MediaStreamTrack
    private let sampleRate: Float
    private var cursor: Double

    init(track: MediaStreamTrack, sampleRate: Float) {
        self.track = track
        self.sampleRate = sampleRate
        cursor = Double(track.currentFrame())
    }

    func render(into output: AudioRenderQuantum) {
        track.render(into: output, cursor: &cursor, outputSampleRate: sampleRate)
    }
}
#endif
