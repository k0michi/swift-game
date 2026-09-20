public struct AudioTimestamp: Sendable, Equatable {
    public var contextTime: Double?
    public var performanceTime: Double?

    public init(
        contextTime: Double? = nil,
        performanceTime: Double? = nil
    ) {
        self.contextTime = contextTime
        self.performanceTime = performanceTime
    }
}
