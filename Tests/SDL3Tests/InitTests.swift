import Testing
@testable import SDL3

@Suite(.serialized)
@MainActor
struct SDL3Tests {
    @Test
    func systemCanBeReinitializedAfterRelease() throws {
        var system: System? = try `init`(flags: [.video])
        #expect(system != nil)

        system = nil
        system = try `init`(flags: [.video])

        #expect(system != nil)
    }

    @Test
    func overlappingInitializationsKeepSubsystemsActive() throws {
        var first: System? = try `init`(flags: [.video])
        var second: System? = try `init`(flags: [.video, .audio])

        #expect(wasInit(flags: [.video, .audio]).contains([.video, .audio]))
        first = nil
        #expect(wasInit(flags: [.video, .audio]).contains([.video, .audio]))
        second = nil
        #expect(!wasInit(flags: [.video, .audio]).contains(.video))
        withExtendedLifetime((first, second)) {}
    }

    @Test
    func initSubsystemWorksWithoutPriorInit() throws {
        var subsystem: Subsystem? = try initSubsystem(flags: [.audio])
        #expect(wasInit(flags: [.audio]).contains(.audio))
        let spec = AudioSpec(format: .f32, channels: 2, freq: 48_000)
        let stream = try createAudioStream(srcSpec: spec, dstSpec: spec)
        subsystem = nil
        #expect(try getAudioStreamAvailable(stream: stream) == 0)
        withExtendedLifetime((subsystem, stream)) {}
    }
}
