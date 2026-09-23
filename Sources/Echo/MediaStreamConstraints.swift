public struct MediaStreamConstraints: Sendable {
    public var video: MediaStreamConstraint
    public var audio: MediaStreamConstraint

    public init(
        video: MediaStreamConstraint = .boolean(false),
        audio: MediaStreamConstraint = .boolean(false)
    ) {
        self.video = video
        self.audio = audio
    }
}
