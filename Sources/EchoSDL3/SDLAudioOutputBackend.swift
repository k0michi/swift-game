import Echo
import SDL3

private final class AudioOutputScratch: @unchecked Sendable {
    let frameCapacity: Int
    let samples: UnsafeMutableBufferPointer<Float>

    init(channelCount: Int, frameCapacity: Int = 4_096) {
        self.frameCapacity = frameCapacity
        samples = .allocate(capacity: channelCount * frameCapacity)
        samples.initialize(repeating: 0)
    }

    deinit {
        samples.deinitialize()
        samples.deallocate()
    }
}

public final class SDLAudioOutputBackend: AudioOutputBackend, @unchecked Sendable {
    public let sampleRate: Float
    public let channelCount: UInt32

    private let stream: SDL3.AudioStream
    private let scratch: AudioOutputScratch

    @MainActor
    public init(
        system: SDL3.System,
        sampleRate: Float? = nil,
        channelCount: UInt32? = nil
    ) throws {
        let deviceSpec = try SDL3.getAudioDeviceFormat(devid: SDL3.audioDeviceDefaultPlayback).spec
        let selectedSampleRate = sampleRate ?? Float(deviceSpec.freq)
        let selectedChannelCount = channelCount ?? UInt32(deviceSpec.channels)
        guard selectedSampleRate.isFinite,
              selectedSampleRate.rounded() == selectedSampleRate,
              (AudioBuffer.minimumSampleRate ... AudioBuffer.maximumSampleRate).contains(selectedSampleRate),
              selectedSampleRate <= Float(Int32.max),
              (1 ... AudioBuffer.maximumNumberOfChannels).contains(selectedChannelCount)
        else { throw WebAudioError.notSupported }

        self.sampleRate = selectedSampleRate
        self.channelCount = selectedChannelCount
        scratch = AudioOutputScratch(channelCount: Int(selectedChannelCount))
        stream = try SDL3.openAudioDeviceStream(
            devid: SDL3.audioDeviceDefaultPlayback,
            spec: SDL3.AudioSpec(
                format: .f32,
                channels: Int32(selectedChannelCount),
                freq: Int32(selectedSampleRate)
            )
        )
        withExtendedLifetime(system) {}
    }

    public func start(
        render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void,
        onError: @escaping @Sendable () -> Void
    ) throws {
        let scratch = self.scratch
        let channels = Int(channelCount)
        let bytesPerFrame = channels * MemoryLayout<Float>.size
        // TODO: Remove SDL wrapper and stream-queue allocations from the callback for strict hard-real-time use.
        try SDL3.setAudioStreamGetCallback(stream: stream) { callbackStream, additionalAmount, _ in
            guard additionalAmount > 0 else { return }
            var framesRemaining = (Int(additionalAmount) + bytesPerFrame - 1) / bytesPerFrame
            while framesRemaining > 0 {
                let frames = min(framesRemaining, scratch.frameCapacity)
                let sampleCount = frames * channels
                let samples = UnsafeMutableBufferPointer(
                    start: scratch.samples.baseAddress,
                    count: sampleCount
                )
                render(samples)
                let bytes = UnsafeRawBufferPointer(
                    start: samples.baseAddress,
                    count: sampleCount * MemoryLayout<Float>.size
                )
                guard (try? SDL3.putAudioStreamData(stream: callbackStream, buf: bytes)) != nil else {
                    onError()
                    return
                }
                framesRemaining -= frames
            }
        }
        do {
            try SDL3.resumeAudioStreamDevice(stream: stream)
        } catch {
            try? SDL3.setAudioStreamGetCallback(stream: stream, callback: nil)
            throw error
        }
    }

    public func stop() throws {
        try SDL3.pauseAudioStreamDevice(stream: stream)
        try SDL3.setAudioStreamGetCallback(stream: stream, callback: nil)
    }
}
