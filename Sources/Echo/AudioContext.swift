import Atomics

@MainActor
public final class AudioContext: BaseAudioContext {
    private let backend: any AudioOutputBackend
    private var controlQueue: RenderControlQueue?
    private var engine: RealtimeRenderEngine?

    public init(
        options: AudioContextOptions = AudioContextOptions(),
        backend: any AudioOutputBackend
    ) throws {
        let sampleRate = options.sampleRate ?? backend.sampleRate
        guard sampleRate.isFinite,
              (AudioBuffer.minimumSampleRate ... AudioBuffer.maximumSampleRate).contains(sampleRate),
              sampleRate == backend.sampleRate,
              (1 ... AudioBuffer.maximumNumberOfChannels).contains(backend.channelCount)
        else { throw WebAudioError.notSupported }

        let quantumSize: UInt32
        switch options.renderSizeHint {
        case .category:
            // TODO: Resolve the hardware category from the selected output backend.
            quantumSize = 128
        case let .frameCount(count):
            guard count >= 1, Double(count) <= 6 * Double(sampleRate) else {
                throw WebAudioError.notSupported
            }
            quantumSize = count
        }
        // TODO: Apply latencyHint and sinkId when backend device selection is exposed.
        self.backend = backend
        super.init(
            sampleRate: sampleRate,
            renderQuantumSize: quantumSize,
            destinationChannelCount: backend.channelCount
        )
        _ = destination
    }

    public func resume() async throws {
        guard state != .closed else { throw WebAudioError.invalidState }
        guard state != .running else { return }
        let plan = try graph.makeRenderPlan(destination: destination, frameCount: Int(renderQuantumSize))
        let queue = RenderControlQueue(initialPlan: plan)
        let engine = try RealtimeRenderEngine(
            controlQueue: queue,
            sampleRate: sampleRate,
            channelCount: destination.maxChannelCount,
            currentFrame: currentFrame
        )
        try backend.start { output in engine.fill(output) }
        controlQueue = queue
        self.engine = engine
        setState(.running)
    }

    public func suspend() async throws {
        guard state != .closed else { throw WebAudioError.invalidState }
        guard state == .running else { return }
        try backend.stop()
        engine = nil
        controlQueue = nil
        setState(.suspended)
    }

    public func close() async throws {
        guard state != .closed else { throw WebAudioError.invalidState }
        if state == .running { try backend.stop() }
        engine = nil
        controlQueue = nil
        setState(.closed)
    }

    override func graphDidChange() {
        guard state == .running, let controlQueue else { return }
        do {
            let plan = try graph.makeRenderPlan(destination: destination, frameCount: Int(renderQuantumSize))
            controlQueue.enqueue(plan)
        } catch {
            // TODO: Propagate asynchronous graph preparation errors through an AudioContext error event.
            try? backend.stop()
            engine = nil
            self.controlQueue = nil
            setState(.closed)
        }
    }
}
