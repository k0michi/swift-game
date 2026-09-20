import Dispatch
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

    @Test
    func rendersSilentQuantumAndAdvancesContextTime() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 48_000))
        var output = AudioBus(numberOfChannels: 2, frameCapacity: 128)
        for channel in 0..<2 {
            for frame in 0..<128 { output[channel, frame] = 1 }
        }

        try context.render(into: &output, frameCount: 128)

        #expect(Array(output.channelData(0, frameCount: 128)) == Array(repeating: 0, count: 128))
        #expect(Array(output.channelData(1, frameCount: 128)) == Array(repeating: 0, count: 128))
        #expect(context.currentTime == 128.0 / 48_000.0)
    }

    @Test
    func appliesControlChangesAtRenderBoundary() throws {
        let context = AudioContext()
        let gain = context.createGain()
        try gain.connect(context.destination)
        gain.gain.value = 0.25

        #expect(context.graph.renderGraph.nodes.isEmpty)
        #expect(context.graph.renderGraph.nodeConnections.isEmpty)

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 128)
        try context.render(into: &output, frameCount: 128)

        #expect(context.graph.renderGraph.nodes[gain.id] != nil)
        #expect(context.graph.renderGraph.nodeConnections.count == 1)
        #expect(context.graph.renderGraph.params[gain.gain.id]?.value == 0.25)

        gain.disconnect()
        #expect(context.graph.renderGraph.nodeConnections.count == 1)
        try context.render(into: &output, frameCount: 128)
        #expect(context.graph.renderGraph.nodeConnections.isEmpty)
    }

    @Test
    func validatesRenderQuantumAndDestinationChannels() throws {
        let context = AudioContext()
        var stereo = AudioBus(numberOfChannels: 2, frameCapacity: 256)
        #expect(throws: AudioRenderError.invalidFrameCount(129)) {
            try context.render(into: &stereo, frameCount: 129)
        }

        var mono = AudioBus(numberOfChannels: 1, frameCapacity: 128)
        #expect(throws: AudioRenderError.insufficientOutputChannels(required: 2, actual: 1)) {
            try context.render(into: &mono, frameCount: 128)
        }
    }

    @Test
    func controlMessageQueueAcceptsConcurrentProducers() {
        let queue = ControlMessageQueue()
        let id = AudioNodeID()

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            queue.enqueue(.setChannelCount(id: id, value: UInt32(index)))
        }

        var values: Set<UInt32> = []
        queue.consume { message in
            guard case .setChannelCount(_, let value) = message else { return }
            values.insert(value)
        }
        #expect(values == Set((0..<1_000).map(UInt32.init)))
    }
}
