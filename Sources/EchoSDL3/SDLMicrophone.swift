import Echo
import SDL3

private final class MicrophoneScratch: @unchecked Sendable {
    let samples: UnsafeMutableBufferPointer<Float>

    init(channelCount: Int) {
        samples = .allocate(capacity: channelCount * 4_096)
        samples.initialize(repeating: 0)
    }

    deinit {
        samples.deinitialize()
        samples.deallocate()
    }
}

@MainActor
public final class SDLMicrophone {
    public let mediaStream: MediaStream
    public let track: MediaStreamTrack

    private let captureStream: SDL3.AudioStream

    public convenience init(
        system: SDL3.System,
        context: AudioContext,
        device: SDL3.AudioDeviceID = SDL3.audioDeviceDefaultRecording
    ) throws {
        try self.init(system: system, sampleRate: context.sampleRate, device: device)
    }

    public convenience init(
        system: SDL3.System,
        sampleRate: Float? = nil,
        device: SDL3.AudioDeviceID = SDL3.audioDeviceDefaultRecording
    ) throws {
        try self.init(system: system, sampleRate: sampleRate, channelCount: nil, device: device)
    }

    init(
        system: SDL3.System,
        sampleRate: Float?,
        channelCount requestedChannelCount: UInt32?,
        device: SDL3.AudioDeviceID
    ) throws {
        guard !SDL3.isAudioDevicePlayback(devid: device) else {
            throw WebAudioError.invalidAccess
        }
        let deviceSpec = try SDL3.getAudioDeviceFormat(devid: device).spec
        guard deviceSpec.channels > 0 else { throw WebAudioError.notSupported }
        let channelCount = requestedChannelCount ?? UInt32(deviceSpec.channels)
        let selectedSampleRate = sampleRate ?? Float(deviceSpec.freq)
        guard (1 ... AudioBuffer.maximumNumberOfChannels).contains(channelCount),
              selectedSampleRate.isFinite,
              selectedSampleRate.rounded() == selectedSampleRate,
              (AudioBuffer.minimumSampleRate ... AudioBuffer.maximumSampleRate).contains(selectedSampleRate),
              selectedSampleRate <= Float(Int32.max)
        else { throw WebAudioError.notSupported }
        let scratch = MicrophoneScratch(channelCount: Int(channelCount))
        let stream = try SDL3.openAudioDeviceStream(
            devid: device,
            spec: SDL3.AudioSpec(
                format: .f32,
                channels: Int32(channelCount),
                freq: Int32(selectedSampleRate)
            )
        )
        let track = try MediaStreamTrack(
            label: (try? SDL3.getAudioDeviceName(devid: device)) ?? "",
            sampleRate: selectedSampleRate,
            channelCount: channelCount,
            onStop: { [stream, system] in
                try? SDL3.pauseAudioStreamDevice(stream: stream)
                try? SDL3.setAudioStreamPutCallback(stream: stream, callback: nil)
                withExtendedLifetime(system) {}
            }
        )
        try SDL3.setAudioStreamPutCallback(stream: stream) { [weak track] callbackStream, _, _ in
            guard let track else { return }
            let bytesPerFrame = Int(channelCount) * MemoryLayout<Float>.size
            while true {
                let available: Int32
                do {
                    available = try SDL3.getAudioStreamAvailable(stream: callbackStream)
                } catch {
                    track.end()
                    return
                }
                guard available >= bytesPerFrame else { return }
                let byteCount = min(Int(available), scratch.samples.count * MemoryLayout<Float>.size)
                    / bytesPerFrame * bytesPerFrame
                let bytes = UnsafeMutableRawBufferPointer(
                    start: scratch.samples.baseAddress,
                    count: byteCount
                )
                let received: Int32
                do {
                    received = try SDL3.getAudioStreamData(stream: callbackStream, buf: bytes)
                } catch {
                    track.end()
                    return
                }
                guard received > 0 else { return }
                let count = Int(received) / MemoryLayout<Float>.size
                _ = track.appendInterleaved(UnsafeBufferPointer(
                    start: scratch.samples.baseAddress,
                    count: count
                ))
            }
        }
        do {
            try SDL3.resumeAudioStreamDevice(stream: stream)
        } catch {
            try? SDL3.setAudioStreamPutCallback(stream: stream, callback: nil)
            throw error
        }
        self.track = track
        mediaStream = MediaStream(tracks: [track])
        captureStream = stream
        withExtendedLifetime(system) {}
    }

    public func stop() throws {
        track.end()
    }
}
