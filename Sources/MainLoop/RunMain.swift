#if os(macOS)
import AppKit
#elseif os(Linux) || os(Windows)
import Foundation
#endif

#if os(macOS) || os(Linux) || os(Windows)
// Runs body as the program on the main actor, then exits: 0 when it returns,
// and with a fatal error when it throws. Call it from a synchronous main.
//
// An async main would not do on the desktop. On macOS, Swift runs its main
// thread with CFRunLoopRun and exits the program when that returns, and
// AppKit's event thread schedules blocks that stop the main run loop, to wake
// the event loop SDL runs inside pollEvent. One of them running while body is
// suspended would end the program. On Linux and Windows, Swift calls
// dispatch_main, which ends the main thread and runs the main actor's jobs on
// another thread from then on, while SDL's windows and events belong to the
// main thread.
//
// Instead the main thread runs a run loop of its own, which runs body as jobs
// of the main queue: on macOS AppKit's, NSApplication.run, which runs again
// when stopped, and elsewhere Foundation's. On macOS, until body makes the
// application, which SDL does when it starts video with a subclass of its
// own, the main run loop runs by itself, so that body starts.
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
            #if os(macOS)
            if let application = NSApp {
                application.run()
            } else {
                CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true)
            }
            #else
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
            #endif
        }
    }
}
#endif
