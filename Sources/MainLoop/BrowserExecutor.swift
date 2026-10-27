#if os(Emscripten)
import CEmscripten
@_spi(ExperimentalCustomExecutors) @_spi(ExperimentalScheduling) import _Concurrency

// The main and default executor in the browser. An executable selects it
// with `typealias DefaultExecutorFactory = BrowserExecutorFactory` in its
// @main type, which Swift reads only with -disable-availability-checking for
// now.
@_spi(ExperimentalCustomExecutors)
public enum BrowserExecutorFactory: ExecutorFactory {
    public static var mainExecutor: any MainExecutor { BrowserExecutor.shared }
    public static var defaultExecutor: any TaskExecutor { BrowserExecutor.shared }
}

// Runs jobs on the browser's event loop: in a task of their own soon after
// they are enqueued, or earlier when an animation frame drains the queue. The
// browser never lets the main thread block, so jobs are run from callbacks
// instead of a run loop.
final class BrowserExecutor: MainExecutor, TaskExecutor, SchedulingExecutor, @unchecked Sendable {
    static let shared = BrowserExecutor()
    private var jobs: [UnownedJob] = []
    private var drainScheduled = false

    public func enqueue(_ job: consuming ExecutorJob) {
        jobs.append(UnownedJob(job))
        guard !drainScheduled else { return }
        drainScheduled = true
        emscripten_set_immediate({ _ in
            BrowserExecutor.shared.drainScheduled = false
            BrowserExecutor.shared.drain()
        }, nil)
    }

    public func enqueue<C: Clock>(
        _ job: consuming ExecutorJob,
        after delay: C.Duration,
        tolerance: C.Duration? = nil,
        clock: C
    ) {
        let duration: Duration
        if C.self == ContinuousClock.self {
            duration = delay as! ContinuousClock.Duration
        } else if C.self == SuspendingClock.self {
            duration = delay as! SuspendingClock.Duration
        } else {
            fatalError("BrowserExecutor cannot schedule on \(C.self)")
        }
        let (seconds, attoseconds) = duration.components
        let milliseconds = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        let job = Unmanaged.passRetained(DelayedJob(UnownedJob(job))).toOpaque()
        emscripten_set_timeout({ job in
            BrowserExecutor.shared.jobs.append(Unmanaged<DelayedJob>.fromOpaque(job!).takeRetainedValue().job)
            BrowserExecutor.shared.drain()
        }, milliseconds, job)
    }

    public var isMainExecutor: Bool { true }

    func drain() {
        while !jobs.isEmpty {
            jobs.removeFirst().runSynchronously(on: asUnownedSerialExecutor())
        }
    }

    // `async main` calls this and exits when it returns. Instead, the queued
    // jobs run and the stack unwinds to the browser, which keeps the runtime
    // alive and calls back into it.
    public func run() throws {
        drain()
        emscripten_exit_with_live_runtime()
    }

    public func stop() {}
}

private final class DelayedJob {
    let job: UnownedJob

    init(_ job: UnownedJob) {
        self.job = job
    }
}
#endif
