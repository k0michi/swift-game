import Dispatch
import Foundation
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

    @Test
    func rendersOscillatorThroughGainIntoDestination() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 8))
        let oscillator = OscillatorNode(
            context: context,
            options: OscillatorOptions(frequency: 2)
        )
        let gain = GainNode(context: context, options: GainOptions(gain: 0.25))
        try oscillator.connect(gain)
        try gain.connect(context.destination)
        oscillator.start()

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 4)
        try context.render(into: &output, frameCount: 4)

        let expected: [Float] = [0, 0.25, 0, -0.25]
        for channel in 0..<2 {
            for frame in 0..<4 {
                #expect(abs(output[channel, frame] - expected[frame]) < 0.000_001)
            }
        }
    }

    @Test
    func schedulesOscillatorStartAndStopAtSampleBoundaries() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 8))
        let oscillator = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 2)
        )
        try oscillator.connect(context.destination)
        oscillator.start(when: 0.25)
        oscillator.stop(when: 0.5)

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 8)
        try context.render(into: &output, frameCount: 8)

        #expect(Array(output.channelData(0, frameCount: 8)) == [0, 0, 1, 1, 0, 0, 0, 0])
        #expect(Array(output.channelData(1, frameCount: 8)) == [0, 0, 1, 1, 0, 0, 0, 0])
    }

    @Test
    func offlineContextRendersOscillatorThroughFinalPartialQuantum() async throws {
        let context = try OfflineAudioContext(
            numberOfChannels: 1,
            length: 300,
            sampleRate: 8_000
        )
        let oscillator = OscillatorNode(
            context: context,
            options: OscillatorOptions(frequency: 1_000)
        )
        try oscillator.connect(context.destination)
        oscillator.start()

        let buffer = try await context.startRendering()
        let samples = try buffer.getChannelData(0)

        #expect(buffer.length == 300)
        #expect(buffer.numberOfChannels == 1)
        #expect(context.currentTime == 300.0 / 8_000.0)
        #expect(context.state == .closed)
        for frame in samples.indices {
            let expected = Float(sin(2 * Double.pi * 1_000 * Double(frame) / 8_000))
            #expect(abs(samples[frame] - expected) < 0.000_001)
        }
    }

    @Test
    func offlineContextRejectsUnsupportedConfiguration() {
        #expect(throws: OfflineAudioContextError.invalidChannelCount) {
            try OfflineAudioContext(numberOfChannels: 0, length: 128, sampleRate: 48_000)
        }
        #expect(throws: OfflineAudioContextError.invalidLength) {
            try OfflineAudioContext(numberOfChannels: 1, length: 0, sampleRate: 48_000)
        }
        #expect(throws: OfflineAudioContextError.invalidSampleRate) {
            try OfflineAudioContext(numberOfChannels: 1, length: 128, sampleRate: 2_999)
        }
    }

    @Test
    func buildsAndInvalidatesTopologicalRenderOrder() throws {
        let context = AudioContext()
        let oscillator = context.createOscillator()
        let gain = context.createGain()
        try oscillator.connect(gain)
        try gain.connect(context.destination)
        oscillator.start()

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 128)
        try context.render(into: &output, frameCount: 128)
        #expect(context.graph.renderGraph.renderOrder == [
            oscillator.id,
            gain.id,
            context.destination.id,
        ])

        gain.disconnect()
        try context.render(into: &output, frameCount: 128)
        let disconnectedOrder = context.graph.renderGraph.renderOrder
        #expect(Set(disconnectedOrder) == Set([oscillator.id, gain.id, context.destination.id]))
        #expect(disconnectedOrder.firstIndex(of: oscillator.id)! < disconnectedOrder.firstIndex(of: gain.id)!)
    }

    @Test
    func mutesOnlyNodesInUnsupportedFeedbackCycles() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 8))
        let oscillator = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 2)
        )
        let first = context.createGain()
        let second = context.createGain()
        try first.connect(second)
        try second.connect(first)
        try second.connect(context.destination)
        try oscillator.connect(context.destination)
        oscillator.start()

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 4)
        try context.render(into: &output, frameCount: 4)

        #expect(context.graph.renderGraph.mutedNodeIDs == Set([first.id, second.id]))
        #expect(Array(output.channelData(0, frameCount: 4)) == [1, 1, -1, -1])
        #expect(context.currentTime == 0.5)
    }

    @Test
    func includesAudioParamInputsInRenderOrder() throws {
        let context = AudioContext()
        let modulationSource = context.createOscillator()
        let gain = context.createGain()
        try modulationSource.connect(gain.gain)
        try gain.connect(context.destination)

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 128)
        try context.render(into: &output, frameCount: 128)

        let order = context.graph.renderGraph.renderOrder
        #expect(order.firstIndex(of: modulationSource.id)! < order.firstIndex(of: gain.id)!)
    }

    @Test
    func appliesAudioRateInputToAudioParamPerSample() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 8))
        let carrier = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 1)
        )
        let modulation = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 2)
        )
        let gain = context.createGain()
        try carrier.connect(gain)
        try modulation.connect(gain.gain)
        try gain.connect(context.destination)
        carrier.start()
        modulation.start()

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 4)
        try context.render(into: &output, frameCount: 4)

        #expect(Array(output.channelData(0, frameCount: 4)) == [2, 2, 0, 0])
    }

    @Test
    func samplesControlRateAudioParamAtStartOfQuantum() throws {
        let context = AudioContext(contextOptions: AudioContextOptions(sampleRate: 8))
        let carrier = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 1)
        )
        let modulation = OscillatorNode(
            context: context,
            options: OscillatorOptions(type: .square, frequency: 2)
        )
        let gain = context.createGain()
        gain.gain.automationRate = .kRate
        try carrier.connect(gain)
        try modulation.connect(gain.gain)
        try gain.connect(context.destination)
        carrier.start()
        modulation.start()

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 4)
        try context.render(into: &output, frameCount: 4)

        #expect(Array(output.channelData(0, frameCount: 4)) == [2, 2, 2, 2])
    }

    @Test
    func routesDistinctInputAndOutputPorts() throws {
        let context = AudioContext()
        let source = MultiOutputTestNode(context: context)
        let merger = MultiInputTestNode(context: context)
        try source.connect(merger, output: 0, input: 0)
        try source.connect(merger, output: 1, input: 1)
        try merger.connect(context.destination)

        var output = AudioBus(numberOfChannels: 2, frameCapacity: 4)
        try context.render(into: &output, frameCount: 4)

        #expect(Array(output.channelData(0, frameCount: 4)) == [3, 3, 3, 3])
    }

    @Test
    func mixesRequiredSpeakerLayoutsAccordingToSpecification() {
        var surround = AudioBus(numberOfChannels: 6, frameCapacity: 1)
        for channel in 0..<6 {
            surround[channel, 0] = Float(channel + 1)
        }
        var stereo = AudioBus(numberOfChannels: 2, frameCapacity: 1)
        AudioBusMixer.mix(
            surround,
            into: &stereo,
            interpretation: .speakers,
            frameCount: 1
        )
        let rootHalf = Float(sqrt(0.5))
        #expect(abs(stereo[0, 0] - (1 + rootHalf * (3 + 5))) < 0.000_001)
        #expect(abs(stereo[1, 0] - (2 + rootHalf * (3 + 6))) < 0.000_001)

        var mono = AudioBus(numberOfChannels: 1, frameCapacity: 1)
        mono[0, 0] = 4
        var discreteStereo = AudioBus(numberOfChannels: 2, frameCapacity: 1)
        AudioBusMixer.mix(
            mono,
            into: &discreteStereo,
            interpretation: .discrete,
            frameCount: 1
        )
        #expect(discreteStereo[0, 0] == 4)
        #expect(discreteStereo[1, 0] == 0)
    }
}

private final class MultiOutputTestNode: AudioNode {
    init(context: BaseAudioContext) {
        super.init(
            context: context,
            numberOfInputs: 0,
            numberOfOutputs: 2,
            options: AudioNodeOptions(),
            processor: MultiOutputTestProcessor()
        )
    }
}

private final class MultiOutputTestProcessor: @unchecked Sendable, RenderNodeProcessor {
    func outputChannelCount(
        output _: Int,
        inputChannelCounts _: [Int],
        node _: RenderNodeState
    ) -> Int {
        1
    }

    func process(
        context: RenderProcessContext,
        inputs _: [AudioBus],
        outputs: inout [AudioBus]
    ) {
        for frame in 0..<context.frameCount {
            outputs[0][0, frame] = 1
            outputs[1][0, frame] = 2
        }
    }
}

private final class MultiInputTestNode: AudioNode {
    init(context: BaseAudioContext) {
        super.init(
            context: context,
            numberOfInputs: 2,
            numberOfOutputs: 1,
            options: AudioNodeOptions(),
            processor: MultiInputTestProcessor()
        )
    }
}

private final class MultiInputTestProcessor: @unchecked Sendable, RenderNodeProcessor {
    func outputChannelCount(
        output _: Int,
        inputChannelCounts _: [Int],
        node _: RenderNodeState
    ) -> Int {
        1
    }

    func process(
        context: RenderProcessContext,
        inputs: [AudioBus],
        outputs: inout [AudioBus]
    ) {
        for frame in 0..<context.frameCount {
            outputs[0][0, frame] = inputs[0][0, frame] + inputs[1][0, frame]
        }
    }
}
