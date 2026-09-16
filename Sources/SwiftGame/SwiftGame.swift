import SDL3

@main
@MainActor
struct SwiftGame {
    static func main() throws {
        let system = try `init`(flags: [.video])

        let window = try createWindow(
            title: "Window",
            w: 1280,
            h: 720,
            flags: [.resizable, .highPixelDensity]
        )

        var isRunning = true

        while isRunning {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested {
                    isRunning = false
                }
            }
        }

        withExtendedLifetime((system, window)) {}
    }
}
