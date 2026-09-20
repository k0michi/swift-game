import Echo
import Testing

@Test func audioContextOptionsUseWebIDLDefaults() {
    let options = AudioContextOptions()

    #expect(options.latencyHint == .category(.interactive))
    #expect(options.sampleRate == nil)
    #expect(options.sinkId == nil)
    #expect(options.renderSizeHint == .category(.default))
}

@Test func offlineAudioContextOptionsUseWebIDLDefaults() {
    let options = OfflineAudioContextOptions(sampleRate: 48_000)

    #expect(options.numberOfChannels == 1)
    #expect(options.length == nil)
    #expect(options.sampleRate == 48_000)
    #expect(options.renderSizeHint == .category(.default))
}

@Test func audioBufferOptionsRequireLengthAndSampleRate() {
    let options = AudioBufferOptions(length: 128, sampleRate: 44_100)

    #expect(options.numberOfChannels == 1)
    #expect(options.length == 128)
    #expect(options.sampleRate == 44_100)
}

@Test func dictionariesWithoutDefaultsPreserveMissingMembers() {
    #expect(AudioTimestamp() == AudioTimestamp(contextTime: nil, performanceTime: nil))
    #expect(AudioNodeOptions() == AudioNodeOptions(
        channelCount: nil,
        channelCountMode: nil,
        channelInterpretation: nil
    ))
}

@Test func webIDLUnionMembersRemainDistinct() {
    #expect(AudioContextLatencyHint.category(.balanced) != .seconds(0))
    #expect(AudioContextRenderSizeHint.category(.hardware) != .frameCount(128))
    #expect(AudioSinkIdentifier.id("device") != .options(AudioSinkOptions(type: .none)))
}
