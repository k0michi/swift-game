public final class OfflineAudioContext: BaseAudioContext {
    public let length: UInt32?
    public let numberOfChannels: UInt32

    // TODO: Replace this closure with EventHandler when Echo has an event abstraction.
    public var oncomplete: ((AudioBuffer) -> Void)?

    private let offlineBackend: OfflineAudioBackend
    private var committedFrames: UInt32 = 0

    public convenience init(
        numberOfChannels: UInt32,
        length: UInt32,
        sampleRate: Float
    ) throws {
        try self.init(contextOptions: OfflineAudioContextOptions(
            numberOfChannels: numberOfChannels,
            length: length,
            sampleRate: sampleRate
        ))
    }

    public init(contextOptions: OfflineAudioContextOptions) throws {
        guard contextOptions.numberOfChannels > 0 else {
            throw OfflineAudioContextError.invalidChannelCount
        }
        if let length = contextOptions.length, length == 0 {
            throw OfflineAudioContextError.invalidLength
        }
        guard contextOptions.sampleRate.isFinite,
              (3_000...768_000).contains(contextOptions.sampleRate)
        else {
            throw OfflineAudioContextError.invalidSampleRate
        }
        let renderQuantumSize: UInt32 = switch contextOptions.renderSizeHint {
        case .default, .hardware:
            128
        case .frames(let frames):
            frames
        }
        guard renderQuantumSize > 0,
              Double(renderQuantumSize) <= 6 * Double(contextOptions.sampleRate)
        else {
            throw OfflineAudioContextError.invalidRenderQuantumSize
        }

        let backend = OfflineAudioBackend(
            sampleRate: contextOptions.sampleRate,
            renderQuantumSize: renderQuantumSize
        )
        offlineBackend = backend
        length = contextOptions.length
        numberOfChannels = contextOptions.numberOfChannels
        super.init(
            backend: backend,
            destinationChannelCount: contextOptions.numberOfChannels
        )
    }

    public func startRendering(chunkSize: UInt32? = nil) async throws -> AudioBuffer {
        guard state != .closed else { throw OfflineAudioContextError.contextClosed }
        let frameCount = try nextFrameCount(chunkSize: chunkSize)
        let buffer = try AudioBuffer(options: AudioBufferOptions(
            numberOfChannels: numberOfChannels,
            length: frameCount,
            sampleRate: sampleRate
        ))

        offlineBackend.setState(.running)
        var frameOffset = 0
        while frameOffset < Int(frameCount) {
            let quantumFrameCount = min(Int(renderQuantumSize), Int(frameCount) - frameOffset)
            var quantum = AudioBus(
                numberOfChannels: Int(numberOfChannels),
                frameCapacity: Int(renderQuantumSize)
            )
            try render(into: &quantum, frameCount: quantumFrameCount)
            for channel in 0..<numberOfChannels {
                try buffer.copyToChannel(
                    from: Array(quantum.channelData(Int(channel), frameCount: quantumFrameCount)),
                    channelNumber: channel,
                    bufferOffset: UInt32(frameOffset)
                )
            }
            frameOffset += quantumFrameCount
        }

        committedFrames += frameCount
        if length.map({ committedFrames >= $0 }) ?? false {
            offlineBackend.setState(.closed)
            oncomplete?(buffer)
        } else {
            offlineBackend.setState(.suspended)
        }
        return buffer
    }

    public func resume() async throws {
        guard state != .closed else { throw OfflineAudioContextError.contextClosed }
        try await offlineBackend.resume()
    }

    // TODO: Implement scheduled offline suspension at a render-quantum boundary.
    public func suspend(suspendTime: Double) async throws {
        _ = suspendTime
        try await offlineBackend.suspend()
    }

    public func close() async throws {
        try await offlineBackend.close()
    }

    private func nextFrameCount(chunkSize: UInt32?) throws -> UInt32 {
        guard let length else {
            return chunkSize ?? renderQuantumSize
        }
        guard committedFrames < length else {
            throw OfflineAudioContextError.renderingComplete
        }
        return min(chunkSize ?? (length - committedFrames), length - committedFrames)
    }
}
