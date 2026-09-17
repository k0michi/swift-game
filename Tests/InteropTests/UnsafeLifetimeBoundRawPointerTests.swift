import Interop
import Testing

@Suite("UnsafeLifetimeBoundRawPointer")
struct UnsafeLifetimeBoundRawPointerTests {
    @Test
    func retainsOwner() throws {
        final class Owner {}

        weak var weakOwner: Owner?
        var pointer: UnsafeLifetimeBoundRawPointer?

        do {
            let owner = Owner()
            weakOwner = owner
            pointer = UnsafeLifetimeBoundRawPointer(
                try #require(UnsafeMutableRawPointer(bitPattern: 1)),
                boundTo: owner
            )
        }

        #expect(weakOwner != nil)
        #expect(pointer != nil)
        pointer = nil
        #expect(weakOwner == nil)
    }
}
