import Atomics

final class RealtimeRenderEngine: @unchecked Sendable {
    private let controlQueue: RenderControlQueue
    private let target: OfflineRenderTarget
    private let currentFrame: ManagedAtomic<UInt64>
    private let channelCount: Int
    private let quantumSize: Int
    private var plan: AudioRenderPlan
    private var nextFrame: UInt64
    private var readFrame: Int

    @MainActor
    init(
        controlQueue: RenderControlQueue,
        sampleRate: Float,
        channelCount: UInt32,
        currentFrame: ManagedAtomic<UInt64>
    ) throws {
        let initialPlan = controlQueue.initialPlan
        let buffer = try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: channelCount,
            length: UInt32(initialPlan.frameCount),
            sampleRate: sampleRate
        ))
        self.controlQueue = controlQueue
        target = try OfflineRenderTarget(buffer: buffer, plan: initialPlan)
        self.currentFrame = currentFrame
        self.channelCount = Int(channelCount)
        quantumSize = initialPlan.frameCount
        plan = initialPlan
        nextFrame = currentFrame.load(ordering: .relaxed)
        readFrame = initialPlan.frameCount
        self.buffer = buffer
    }

    private let buffer: AudioBuffer

    func fill(_ output: UnsafeMutableBufferPointer<Float>) {
        guard output.count.isMultiple(of: channelCount) else {
            output.update(repeating: 0)
            return
        }
        var outputFrame = 0
        let requestedFrames = output.count / channelCount
        while outputFrame < requestedFrames {
            if readFrame == quantumSize {
                while let replacement = controlQueue.dequeue() {
                    guard replacement.frameCount == quantumSize,
                          replacement.destinationChannelCount == channelCount
                    else {
                        output.update(repeating: 0)
                        return
                    }
                    plan = replacement
                }
                controlQueue.acknowledgeAppliedPlan()
                plan.render(at: nextFrame, into: target, offset: 0)
                nextFrame += UInt64(quantumSize)
                currentFrame.store(nextFrame, ordering: .releasing)
                readFrame = 0
            }
            let count = min(requestedFrames - outputFrame, quantumSize - readFrame)
            for frame in 0 ..< count {
                for channel in 0 ..< channelCount {
                    output[(outputFrame + frame) * channelCount + channel] =
                        target.channelData(channel)[readFrame + frame]
                }
            }
            outputFrame += count
            readFrame += count
        }
        withExtendedLifetime(buffer) {}
    }
}
