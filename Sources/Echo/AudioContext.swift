import Atomics

@MainActor
public final class AudioContext: BaseAudioContext {
    public var onerror: (() -> Void)?

    private let backend: any AudioOutputBackend
    private var controlQueue: RenderControlQueue?
    private var engine: RealtimeRenderEngine?
    private let backendFailed = ManagedAtomic(false)
    private var errorMonitor: Task<Void, Never>?

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
        backendFailed.store(false, ordering: .relaxed)
        try backend.start(render: { output in engine.fill(output) }, onError: { [backendFailed] in
            backendFailed.store(true, ordering: .releasing)
        })
        controlQueue = queue
        self.engine = engine
        setState(.running)
        errorMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                guard let self else { return }
                if backendFailed.exchange(false, ordering: .acquiring) {
                    await handleBackendFailure()
                    return
                }
            }
        }
    }

    public func suspend() async throws {
        guard state != .closed else { throw WebAudioError.invalidState }
        guard state == .running else { return }
        try backend.stop()
        errorMonitor?.cancel()
        errorMonitor = nil
        engine = nil
        controlQueue = nil
        setState(.suspended)
    }

    public func close() async throws {
        guard state != .closed else { throw WebAudioError.invalidState }
        if state == .running { try backend.stop() }
        errorMonitor?.cancel()
        errorMonitor = nil
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
            try? backend.stop()
            errorMonitor?.cancel()
            errorMonitor = nil
            engine = nil
            self.controlQueue = nil
            onerror?()
            setState(.closed)
        }
    }

    private func handleBackendFailure() async {
        guard state == .running else { return }
        try? backend.stop()
        engine = nil
        controlQueue = nil
        errorMonitor = nil
        onerror?()
        setState(.suspended)
    }
}
