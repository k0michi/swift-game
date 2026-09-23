import Atomics
import Foundation

public final class MediaStreamTrack: @unchecked Sendable {
    public let id: String
    public let kind = "audio"
    public let label: String
    public var sampleRate: Float { source.sampleRate }
    public var channelCount: UInt32 { source.channelCount }
    public var readyState: MediaStreamTrackState { ended ? .ended : .live }
    public var ended: Bool {
        stopped.load(ordering: .acquiring) || source.ended.load(ordering: .acquiring)
    }
    public var enabled: Bool {
        get { isEnabled.load(ordering: .acquiring) }
        set { isEnabled.store(newValue, ordering: .releasing) }
    }
    public var muted: Bool { isMuted.load(ordering: .acquiring) }

    let source: MediaStreamTrackSource
    private let stopped = ManagedAtomic(false)
    private let isEnabled = ManagedAtomic(true)
    private let isMuted = ManagedAtomic(false)

    public init(
        id: String = UUID().uuidString,
        label: String = "",
        sampleRate: Float,
        channelCount: UInt32,
        onStop: @escaping @Sendable () -> Void = {}
    ) throws {
        guard sampleRate.isFinite,
              (AudioBuffer.minimumSampleRate ... AudioBuffer.maximumSampleRate).contains(sampleRate),
              (1 ... AudioBuffer.maximumNumberOfChannels).contains(channelCount)
        else { throw WebAudioError.notSupported }
        self.id = id
        self.label = label
        source = MediaStreamTrackSource(
            sampleRate: sampleRate,
            channelCount: channelCount,
            label: label,
            onStop: onStop
        )
    }

    private init(id: String, source: MediaStreamTrackSource, enabled: Bool, muted: Bool) {
        self.id = id
        label = source.label
        self.source = source
        isEnabled.store(enabled, ordering: .relaxed)
        isMuted.store(muted, ordering: .relaxed)
        source.retainTrack()
    }

    deinit {
        if !stopped.load(ordering: .relaxed) {
            source.releaseTrack()
        }
    }

    public func clone() -> MediaStreamTrack {
        let track = MediaStreamTrack(
            id: UUID().uuidString,
            source: source,
            enabled: enabled,
            muted: muted
        )
        if ended { track.stop() }
        return track
    }

    public func stop() {
        if !stopped.exchange(true, ordering: .acquiringAndReleasing) {
            source.releaseTrack()
        }
    }

    public func end() {
        source.end()
    }

    public func getSettings() -> MediaTrackSettings {
        ended ? MediaTrackSettings() : MediaTrackSettings(
            sampleRate: UInt32(sampleRate),
            channelCount: channelCount
        )
    }

    @discardableResult
    public func appendInterleaved(_ input: UnsafeBufferPointer<Float>) -> Int {
        source.appendInterleaved(input)
    }

    func currentFrame() -> UInt64 { source.currentFrame() }

    func render(into output: AudioRenderQuantum, cursor: inout Double, outputSampleRate: Float) {
        if ended {
            output.setChannelCount(1)
            return
        }
        source.render(
            into: output,
            cursor: &cursor,
            outputSampleRate: outputSampleRate,
            silent: !enabled || muted
        )
    }

    // TODO: Add Media Capture constraint/capability APIs and source event handlers.
}
