import Atomics

public final class OfflineAudioContext: BaseAudioContext {
    public let length: UInt32?
    public var oncomplete: ((OfflineAudioCompletionEvent) -> Void)?

    private let numberOfChannels: UInt32
    private var committedFrames: UInt64 = 0
    private var renderedFrames: UInt64 = 0
    private var renderingStarted = false
    private var isRendering = false
    private let renderCancelled = ManagedAtomic(false)
    private var activeControlQueue: RenderControlQueue?
    private var renderControlError: Error?

    public init(options: OfflineAudioContextOptions) throws {
        let renderQuantumSize = try Self.resolveRenderQuantumSize(
            options.renderSizeHint,
            sampleRate: options.sampleRate
        )

        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(options.numberOfChannels),
              options.sampleRate.isFinite,
              (AudioBuffer.minimumSampleRate ... AudioBuffer.maximumSampleRate).contains(options.sampleRate),
              options.length.map({ $0 > 0 }) ?? true
        else {
            throw WebAudioError.notSupported
        }

        numberOfChannels = options.numberOfChannels
        length = options.length
        super.init(
            sampleRate: options.sampleRate,
            renderQuantumSize: renderQuantumSize,
            destinationChannelCount: options.numberOfChannels
        )
        _ = destination
    }

    public convenience init(
        numberOfChannels: UInt32,
        length: UInt32,
        sampleRate: Float
    ) throws {
        try self.init(options: OfflineAudioContextOptions(
            numberOfChannels: numberOfChannels,
            length: length,
            sampleRate: sampleRate
        ))
    }

    public func startRendering(chunkSize: UInt32? = nil) async throws -> AudioBuffer {
        guard state != .closed,
              !isRendering,
              length.map({ committedFrames < UInt64($0) }) ?? true
        else {
            throw WebAudioError.invalidState
        }

        let remainingLength = length.map { UInt64($0) - committedFrames }
        let requestedLength = remainingLength.map { remaining in
            min(UInt64(chunkSize ?? UInt32(clamping: remaining)), remaining)
        } ?? UInt64(chunkSize ?? renderQuantumSize)
        let bufferLength = try roundedToRenderQuantum(requestedLength)
        let buffer = try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: numberOfChannels,
            length: bufferLength,
            sampleRate: sampleRate
        ))
        let plan = try graph.makeRenderPlan(destination: destination, frameCount: Int(renderQuantumSize))
        let controlQueue = RenderControlQueue(initialPlan: plan)

        renderingStarted = true
        isRendering = true
        activeControlQueue = controlQueue
        renderControlError = nil
        renderCancelled.store(false, ordering: .releasing)
        defer {
            isRendering = false
            activeControlQueue = nil
            renderControlError = nil
        }
        committedFrames += UInt64(bufferLength)
        setState(.running)

        let result: OfflineRenderResult
        do {
            result = try await OfflineRenderWorker.render(
                controlQueue: controlQueue,
                into: OfflineRenderBuffer(value: buffer),
                from: renderFrame,
                currentFrame: currentFrame,
                cancelled: renderCancelled
            )
        } catch {
            if state != .closed { setState(.suspended) }
            throw renderControlError ?? error
        }
        guard state != .closed else { throw WebAudioError.invalidState }
        renderedFrames += UInt64(bufferLength)

        if let length, renderedFrames >= UInt64(length) {
            setState(.closed)
            oncomplete?(OfflineAudioCompletionEvent(renderedBuffer: buffer))
        } else {
            setState(.suspended)
        }

        return result.buffer
    }

    public func close() async throws {
        guard state != .closed else {
            throw WebAudioError.invalidState
        }

        renderCancelled.store(true, ordering: .releasing)
        setState(.closed)
    }

    override func graphDidChange() {
        guard isRendering, state != .closed, let activeControlQueue else { return }
        do {
            let plan = try graph.makeRenderPlan(destination: destination, frameCount: Int(renderQuantumSize))
            activeControlQueue.enqueue(plan)
        } catch {
            renderControlError = error
            renderCancelled.store(true, ordering: .releasing)
        }
    }

    // TODO: Implement suspend(at:) and resume() with render-quantum synchronization.

    private static func resolveRenderQuantumSize(
        _ hint: AudioContextRenderSizeHint,
        sampleRate: Float
    ) throws -> UInt32 {
        switch hint {
        case .category:
            128
        case let .frameCount(frameCount):
            if frameCount >= 1, Double(frameCount) <= 6 * Double(sampleRate) {
                frameCount
            } else {
                throw WebAudioError.notSupported
            }
        }
    }

    private func roundedToRenderQuantum(_ frameCount: UInt64) throws -> UInt32 {
        guard frameCount > 0 else {
            throw WebAudioError.notSupported
        }

        let quantum = UInt64(renderQuantumSize)
        let rounded = ((frameCount + quantum - 1) / quantum) * quantum
        guard let result = UInt32(exactly: rounded) else {
            throw WebAudioError.notSupported
        }
        return result
    }
}
