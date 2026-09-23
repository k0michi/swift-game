import Echo
import SDL3

@MainActor
public final class SDLMediaCaptureBackend: MediaCaptureBackend {
    private let system: SDL3.System

    public init(system: SDL3.System) {
        self.system = system
    }

    public func enumerateDevices() async throws -> [MediaDeviceInfo] {
        let recording = try SDL3.getAudioRecordingDevices().map { device in
            MediaDeviceInfo(
                deviceId: String(device.rawValue),
                kind: .audioinput,
                label: try SDL3.getAudioDeviceName(devid: device)
            )
        }
        let playback = try SDL3.getAudioPlaybackDevices().map { device in
            MediaDeviceInfo(
                deviceId: String(device.rawValue),
                kind: .audiooutput,
                label: try SDL3.getAudioDeviceName(devid: device)
            )
        }
        return recording + playback
    }

    public func getUserMedia(_ constraints: MediaStreamConstraints) async throws -> MediaStream {
        guard constraints.audio.requested, !constraints.video.requested else {
            throw WebAudioError.notSupported
        }
        let options: MediaTrackConstraints?
        switch constraints.audio {
        case .boolean: options = nil
        case let .constraints(value): options = value
        }
        let device: SDL3.AudioDeviceID
        if let deviceId = options?.deviceId {
            guard let selected = try SDL3.getAudioRecordingDevices().first(where: {
                String($0.rawValue) == deviceId
            }) else { throw WebAudioError.notSupported }
            device = selected
        } else {
            device = SDL3.audioDeviceDefaultRecording
        }
        let microphone = try SDLMicrophone(
            system: system,
            sampleRate: options?.sampleRate.map(Float.init),
            channelCount: options?.channelCount,
            device: device
        )
        return microphone.mediaStream
    }
}
