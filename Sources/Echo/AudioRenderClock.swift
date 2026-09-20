import Foundation

final class AudioRenderClock {
    // TODO: Replace this lock with a cross-platform atomic Int64 before real-time rendering.
    // Synchronization.Atomic requires macOS 15, while Echo currently supports macOS 11.
    // advance(by:) will run on the audio callback thread and must not block.
    private let lock = NSLock()
    private var frames: Int64 = 0

    var renderedFrames: Int64 {
        lock.withLock { frames }
    }

    func advance(by frameCount: Int) {
        lock.withLock { frames += Int64(frameCount) }
    }
}
