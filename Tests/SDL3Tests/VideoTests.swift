import Testing
@testable import SDL3

@MainActor
extension SDL3Tests {
    @Test
    func createsHiddenWindowWithDummyDriver() throws {
        let system = try `init`(flags: [.video])
        let window = try createWindow(
            title: "SDL3Tests",
            w: 320,
            h: 240,
            flags: [.hidden, .resizable]
        )

        withExtendedLifetime((system, window)) {}
    }

    @Test
    func windowKeepsSystemAlive() throws {
        weak var weakSystem: System?
        var window: Window?

        do {
            let system = try `init`(flags: [.video])
            weakSystem = system
            window = try createWindow(
                title: "SDL3Tests",
                w: 1,
                h: 1,
                flags: [.hidden]
            )
        }

        #expect(weakSystem != nil)
        #expect(window != nil)
        window = nil
        #expect(weakSystem == nil)
    }
}
