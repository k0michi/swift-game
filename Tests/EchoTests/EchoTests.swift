import Testing
@testable import Echo

@Suite
struct EchoTests {
    @Test
    func contextBuildsAndConnectsGraph() throws {
        let context = AudioContext()
        let gain = context.createGain()

        #expect(gain.context === context)
        #expect(try gain.connect(context.destination) === context.destination)
        gain.disconnect()
    }

    @Test
    func nodeKeepsItsContextAndGraphAlive() {
        weak var weakContext: AudioContext?
        var node: GainNode?
        do {
            let context = AudioContext()
            weakContext = context
            node = context.createGain()
        }

        #expect(node != nil)
        #expect(weakContext != nil)
        node = nil
        #expect(weakContext == nil)
    }

    @Test
    func rejectsConnectionsBetweenContexts() {
        let source = AudioContext().createGain()
        let destination = AudioContext().createGain()

        #expect(throws: AudioGraphError.differentContext) {
            try source.connect(destination)
        }
    }

    @Test
    func createsAndCopiesAudioBufferChannels() throws {
        let context = AudioContext()
        let buffer = try context.createBuffer(numberOfChannels: 2, length: 4, sampleRate: 48_000)
        try buffer.copyToChannel(from: [1, 0.5], channelNumber: 1, bufferOffset: 1)

        #expect(try buffer.getChannelData(1) == [0, 1, 0.5, 0])
        #expect(buffer.duration == 4.0 / 48_000.0)
    }
}
