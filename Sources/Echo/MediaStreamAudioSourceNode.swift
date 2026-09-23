@MainActor
public final class MediaStreamAudioSourceNode: AudioNode {
    public let mediaStream: MediaStream
    let renderState: MediaStreamRenderState

    public init(context: AudioContext, options: MediaStreamAudioSourceOptions) throws {
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
