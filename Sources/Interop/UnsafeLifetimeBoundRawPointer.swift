public struct UnsafeLifetimeBoundRawPointer {
    private let pointer: UnsafeMutableRawPointer
    private let owner: AnyObject

    public init<Owner: AnyObject>(
        _ pointer: UnsafeMutableRawPointer,
        boundTo owner: Owner
    ) {
        self.pointer = pointer
        self.owner = owner
    }

    public func withUnsafeMutableRawPointer<Result>(
        _ body: (UnsafeMutableRawPointer) throws -> Result
    ) rethrows -> Result {
        try withExtendedLifetime(owner) {
            try body(pointer)
        }
    }
}
