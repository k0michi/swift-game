import Echo
import Testing

@Test func audioBufferStartsSilentAndComputesDuration() throws {
    let buffer = try AudioBuffer(options: AudioBufferOptions(
        numberOfChannels: 2,
        length: 24_000,
        sampleRate: 48_000
    ))

    #expect(buffer.numberOfChannels == 2)
    #expect(buffer.length == 24_000)
    #expect(buffer.sampleRate == 48_000)
    #expect(buffer.duration == 0.5)
    #expect(try buffer.getChannelData(0).allSatisfy { $0 == 0 })
}

@Test func channelDataIsAWriteThroughView() throws {
    let buffer = try AudioBuffer(options: AudioBufferOptions(length: 2, sampleRate: 48_000))
    let firstView = try buffer.getChannelData(0)
    firstView[1] = 0.75

    let secondView = try buffer.getChannelData(0)
    #expect(secondView[1] == 0.75)
}

@Test func channelCopiesAreClampedToTheBufferLength() throws {
    let buffer = try AudioBuffer(options: AudioBufferOptions(length: 3, sampleRate: 48_000))
    let source: [Float] = [1, 2, 3]
    try buffer.copyToChannel(source, channelNumber: 0, bufferOffset: 2)

    var destination: [Float] = [-1, -1, -1]
    try buffer.copyFromChannel(&destination, channelNumber: 0, bufferOffset: 1)

    #expect(destination == [0, 1, -1])
}

@Test func invalidAudioBufferOptionsAreRejected() {
    #expect(throws: WebAudioError.notSupported) {
        try AudioBuffer(options: AudioBufferOptions(numberOfChannels: 0, length: 1, sampleRate: 48_000))
    }
    #expect(throws: WebAudioError.notSupported) {
        try AudioBuffer(options: AudioBufferOptions(length: 0, sampleRate: 48_000))
    }
    #expect(throws: WebAudioError.notSupported) {
        try AudioBuffer(options: AudioBufferOptions(length: 1, sampleRate: 2_999))
    }
    #expect(throws: WebAudioError.notSupported) {
        try AudioBuffer(options: AudioBufferOptions(length: 1, sampleRate: .nan))
    }
}

@Test func invalidChannelIndexIsRejected() throws {
    let buffer = try AudioBuffer(options: AudioBufferOptions(length: 1, sampleRate: 48_000))

    #expect(throws: WebAudioError.indexSize) {
        try buffer.getChannelData(1)
    }
}
