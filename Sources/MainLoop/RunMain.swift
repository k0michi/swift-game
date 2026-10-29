#if os(macOS)
import AppKit

// Runs body as the program on the main actor, then exits: 0 when it returns,
// and with a fatal error when it throws. Call it from a synchronous main.
//
// An async main would not do on macOS. Swift runs its main thread with
// CFRunLoopRun and exits the program when that returns, and AppKit's event
// thread schedules blocks that stop the main run loop, to wake the event loop
// SDL runs inside pollEvent. One of them running while body is suspended
// would end the program. AppKit's own run loop, NSApplication.run, runs again
// when stopped, so body runs under it instead, as jobs of the main queue.
//
// Until body makes the application, which SDL does when it starts video with
// a subclass of its own, the main run loop runs by itself, so that body
// starts.
public func runMain(_ body: @MainActor @escaping () async throws -> Void) -> Never {
    MainActor.assumeIsolated {
        Task { @MainActor in
            do {
                try await body()
            } catch {
                fatalError("\(error)")
            }
            exit(0)
        }
        while true {
            if let application = NSApp {
                application.run()
            } else {
                CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true)
            }
        }
    }
}
#endif
