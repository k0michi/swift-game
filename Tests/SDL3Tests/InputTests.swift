import Testing
@testable import SDL3

@MainActor
extension SDL3Tests {
    @Test
    func keyboardAndMouseStateAreReadable() throws {
        let system = try `init`(flags: [.video])

        pumpEvents()

        let keyboard = getKeyboardState()
        let mouse = getMouseState()

        #expect(!keyboard[.unknown])
        #expect(mouse.x.isFinite)
        #expect(mouse.y.isFinite)
        withExtendedLifetime(system) {}
    }

    @Test
    func keycodeExposesEmbeddedScancode() {
        #expect(Keycode.left.isScancode)
        #expect(Keycode.left.scancode == .left)
        #expect(!Keycode.a.isScancode)
        #expect(Keycode.a.scancode == nil)
    }

    @Test
    func completeScancodeRangeIsAvailable() {
        #expect(Scancode.unknown.rawValue == 0)
        #expect(Scancode.reserved.rawValue == 400)
        #expect(Scancode.count.rawValue == 512)
    }
}
