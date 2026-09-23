import Foundation

@MainActor
public final class MediaStream {
    public let id = UUID().uuidString
    public var onaddtrack: ((MediaStreamTrack) -> Void)?
    public var onremovetrack: ((MediaStreamTrack) -> Void)?
    public var active: Bool { tracks.contains { !$0.ended } }

    private var tracks: [MediaStreamTrack] = []

    public init() {}

    public convenience init(_ stream: MediaStream) {
        self.init(tracks: stream.getTracks())
    }

    public init(tracks: [MediaStreamTrack]) {
        for track in tracks where !self.tracks.contains(where: { $0 === track }) {
            self.tracks.append(track)
        }
    }

    public func getAudioTracks() -> [MediaStreamTrack] { tracks }

    public func getVideoTracks() -> [MediaStreamTrack] { [] }

    public func getTracks() -> [MediaStreamTrack] { tracks }

    public func getTrackById(_ trackId: String) -> MediaStreamTrack? {
        tracks.first { $0.id == trackId }
    }

    public func addTrack(_ track: MediaStreamTrack) {
        guard !tracks.contains(where: { $0 === track }) else { return }
        tracks.append(track)
        onaddtrack?(track)
    }

    public func removeTrack(_ track: MediaStreamTrack) {
        guard let index = tracks.firstIndex(where: { $0 === track }) else { return }
        tracks.remove(at: index)
        onremovetrack?(track)
    }

    public func clone() -> MediaStream {
        MediaStream(tracks: tracks.map { $0.clone() })
    }

    // TODO: Add video-track support and EventTarget-style event dispatch.
}
