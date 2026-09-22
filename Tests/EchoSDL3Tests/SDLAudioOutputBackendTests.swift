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
