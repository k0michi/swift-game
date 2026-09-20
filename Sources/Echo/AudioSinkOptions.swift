public struct AudioSinkOptions: Sendable, Equatable {
    public var type: AudioSinkType

    public init(type: AudioSinkType) {
        self.type = type
    }
}
