import Testing
@testable import SDL3

@Suite(.serialized)
@MainActor
struct SDL3Tests {
    @Test
    func systemCanBeReinitializedAfterRelease() throws {
        var system: System? = try `init`(flags: [.video])
        #expect(system != nil)

        system = nil
        system = try `init`(flags: [.video])

        #expect(system != nil)
    }

    @Test
    func secondSystemIsRejected() throws {
        let system = try `init`(flags: [.video])

        #expect(throws: SDLError.self) {
            _ = try `init`(flags: [.video])
        }

        withExtendedLifetime(system) {}
    }
}
