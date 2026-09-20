import Atomics

final class AudioRenderClock {
    private let frames = ManagedAtomic<Int64>(0)

    var renderedFrames: Int64 {
        frames.load(ordering: .relaxed)
    }

    func advance(by frameCount: Int) {
        frames.wrappingIncrement(by: Int64(frameCount), ordering: .relaxed)
    }
}
