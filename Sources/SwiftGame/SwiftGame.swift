import SDL3

@main
@MainActor
struct SwiftGame {
    static func main() throws {
        try SDL.initialize()
        defer { SDL.shutdown() }

        print("SDL3 initialized successfully")
    }
}
