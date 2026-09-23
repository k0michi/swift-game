import Echo
import EchoSDL3
import Foundation
import SDL3
import Testing

@MainActor
@Test func sdlBackendDrivesRealtimeContext() async throws {
    guard ProcessInfo.processInfo.environment["ECHO_SDL_AUDIO_TEST"] == "1" else { return }
    let system = try SDL3.`init`(flags: [.audio])
    let backend = try SDLAudioOutputBackend(system: system, sampleRate: 48_000, channelCount: 2)
    let context = try AudioContext(backend: backend)
    let source = context.createConstantSource()
    try source.start()
    try source.connect(context.destination)

    try await context.resume()
    try await Task.sleep(for: .milliseconds(50))
    try await context.suspend()
    #expect(context.currentTime > 0)
    try await context.close()
    #expect(context.state == .closed)
}

@MainActor
@Test func sdlMicrophoneCreatesMediaStreamSource() async throws {
    guard ProcessInfo.processInfo.environment["ECHO_SDL_AUDIO_TEST"] == "1" else { return }
    let system = try SDL3.`init`(flags: [.audio])
    let backend = try SDLAudioOutputBackend(system: system, sampleRate: 48_000, channelCount: 2)
    let context = try AudioContext(backend: backend)
    let microphone = try SDLMicrophone(system: system, context: context)
    let source = try context.createMediaStreamSource(microphone.mediaStream)
    try source.connect(context.destination)

    try await context.resume()
    try await Task.sleep(for: .milliseconds(50))
    microphone.track.stop()
    try microphone.stop()
    try await context.close()
    #expect(microphone.track.ended)
    #expect(context.currentTime > 0)
}

@MainActor
@Test func sdlGetUserMediaCreatesConnectableAudioStream() async throws {
    guard ProcessInfo.processInfo.environment["ECHO_SDL_AUDIO_TEST"] == "1" else { return }
    let system = try SDL3.`init`(flags: [.audio])
    let stream = try await MediaDevices(backend: SDLMediaCaptureBackend(system: system))
        .getUserMedia(MediaStreamConstraints(audio: .boolean(true)))
    #expect(stream.getAudioTracks().count == 1)
    #expect(stream.active)
    #expect(stream.getAudioTracks()[0].kind == "audio")

    let output = try SDLAudioOutputBackend(system: system, sampleRate: 48_000, channelCount: 2)
    let context = try AudioContext(backend: output)
    let source = try context.createMediaStreamSource(stream)
    try source.connect(context.destination)
    try await context.resume()
    try await Task.sleep(for: .milliseconds(50))
    stream.getAudioTracks()[0].stop()
    #expect(!stream.active)
    try await context.close()
}
