// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

// Prepared on the control actor, then used exclusively by one rendering thread.
final class AudioRenderPlan: @unchecked Sendable {
    enum Processor: Sendable {
        case passThrough
        case constant(
            startFrame: UInt64?,
            stopFrame: UInt64?,
            ended: EndedSignal,
            parameter: AudioParamTimeline,
            paramSources: [Int]
        )
        case delay(
            state: DelayRenderState,
            parameter: AudioParamTimeline,
            paramSources: [Int]
        )
        case gain(parameter: AudioParamTimeline, paramSources: [Int])
        case mediaStream(state: MediaStreamRenderState)
        case stereoPanner(parameter: AudioParamTimeline, paramSources: [Int])
        // `paramSources` are those of playbackRate and of detune.
        case bufferSource(
            state: BufferSourceRenderState,
            ended: EndedSignal,
            sampleRate: Float,
            schedule: BufferSourceRenderState.Schedule,
            playbackRate: AudioParamTimeline,
            detune: AudioParamTimeline,
            paramSources: [[Int]]
        )
        // `parameters` and `paramSources` are those of frequency, detune, Q
        // and gain.
        case biquad(
            state: BiquadRenderState,
            type: BiquadFilterType,
            sampleRate: Float,
            parameters: [AudioParamTimeline],
            paramSources: [[Int]]
        )
        // `paramSources` are those of frequency and of detune.
        case oscillator(
            state: OscillatorRenderState,
            ended: EndedSignal,
            wave: WaveTable,
            sampleRate: Float,
            startTime: Double?,
            stopTime: Double?,
            frequency: AudioParamTimeline,
            detune: AudioParamTimeline,
            paramSources: [[Int]]
        )
        case waveShaper(state: WaveShaperRenderState, curve: [Float]?, oversample: OverSampleType)
    }

    struct NodeConfiguration: Sendable {
        let inputChannelCount: Int?
        let outputChannelCount: Int
        let interpretation: ChannelInterpretation
        let channelCount: Int
        let channelCountMode: ChannelCountMode
        let sources: [Int]
        let isMuted: Bool
        let isCycleBreaker: Bool
        let sounding: SoundingSignal?
        let processor: Processor
    }

    private final class Slot {
        let configuration: NodeConfiguration
        let input: AudioRenderQuantum?
        let output: AudioRenderQuantum
        // What is connected to each of the node's parameters, mixed to mono,
        // or nil for a parameter nothing is connected to.
        let paramInputs: [AudioRenderQuantum?]
        var paramInput: AudioRenderQuantum? { paramInputs.first ?? nil }

        init(configuration: NodeConfiguration, frameCount: Int) {
            self.configuration = configuration
            input = configuration.inputChannelCount.map {
                AudioRenderQuantum(
                    channelCapacity: Self.inputChannelCapacity(configuration.processor) ?? $0,
                    frameCount: frameCount, channelCount: $0
                )
            }
            output = AudioRenderQuantum(
                channelCapacity: Self.outputFollowsInput(configuration.processor) || Self.isBufferSource(configuration.processor)
                    ? Int(AudioBuffer.maximumNumberOfChannels) : configuration.outputChannelCount,
                frameCount: frameCount, channelCount: configuration.outputChannelCount
            )
            paramInputs = Self.paramSources(configuration.processor).map { sources in
                sources.isEmpty ? nil : AudioRenderQuantum(channelCapacity: 1, frameCount: frameCount)
            }
        }

        // The sources connected to each of the node's parameters.
        static func paramSources(_ processor: Processor) -> [[Int]] {
            switch processor {
            case let .constant(_, _, _, _, sources), let .delay(_, _, sources), let .gain(_, sources),
                 let .stereoPanner(_, sources):
                [sources]
            case let .oscillator(_, _, _, _, _, _, _, _, sources), let .biquad(_, _, _, _, sources),
                 let .bufferSource(_, _, _, _, _, _, sources):
                sources
            case .passThrough, .mediaStream, .waveShaper:
                []
            }
        }

        // Whether the output has as many channels as the input, however many.
        private static func outputFollowsInput(_ processor: Processor) -> Bool {
            switch processor {
            case .delay, .gain, .waveShaper, .biquad: true
            case .passThrough, .constant, .mediaStream, .stereoPanner, .oscillator, .bufferSource: false
            }
        }

        // A buffer source's output has as many channels as its buffer.
        private static func isBufferSource(_ processor: Processor) -> Bool {
            if case .bufferSource = processor { return true }
            return false
        }

        // The most channels the input can have, when its first count is not.
        private static func inputChannelCapacity(_ processor: Processor) -> Int? {
            switch processor {
            case .passThrough, .delay, .gain, .waveShaper, .biquad: Int(AudioBuffer.maximumNumberOfChannels)
            case .stereoPanner: 2
            case .constant, .mediaStream, .oscillator, .bufferSource: nil
            }
        }
    }

    let frameCount: Int
    let destinationChannelCount: Int
    private let slots: [Slot]
    private let destinationIndex: Int

    init(configurations: [NodeConfiguration], frameCount: Int, destinationIndex: Int) {
        self.frameCount = frameCount
        self.destinationIndex = destinationIndex
        destinationChannelCount = configurations[destinationIndex].outputChannelCount
        slots = configurations.map { Slot(configuration: $0, frameCount: frameCount) }
    }

    func render(at frame: UInt64, into target: OfflineRenderTarget, offset: Int) {
        for slot in slots {
            slot.input?.clear()
            slot.output.clear()

            let configuration = slot.configuration
            if configuration.isMuted { continue }

            if let input = slot.input, !configuration.isCycleBreaker {
                configureInput(input, for: configuration)
                input.clear()
                for sourceIndex in configuration.sources {
                    ChannelMixer.mix(
                        slots[sourceIndex].output,
                        into: input,
                        interpretation: configuration.interpretation
                    )
                }
            }

            switch configuration.processor {
            case .passThrough:
                if let input = slot.input {
                    ChannelMixer.mix(input, into: slot.output, interpretation: configuration.interpretation)
                }
            case let .mediaStream(state):
                state.render(into: slot.output)
            case let .gain(parameter, _):
                mixParamInputs(of: slot)
                guard let input = slot.input else { continue }
                slot.output.setChannelCount(input.channelCount)
                for index in 0 ..< input.frameCount {
                    let modulationIndex = parameter.automationRate == .kRate ? 0 : index
                    let modulation = slot.paramInput.map { $0.channelData(0)[modulationIndex] } ?? 0
                    let gain = parameter.computedValue(
                        at: frame + UInt64(index),
                        quantumStart: frame,
                        modulation: modulation
                    )
                    for channel in 0 ..< input.channelCount {
                        slot.output.channelData(channel)[index] = input.channelData(channel)[index] * gain
                    }
                }
            case let .stereoPanner(parameter, _):
                mixParamInputs(of: slot)
                guard let input = slot.input else { continue }
                StereoPanning.render(input: input, output: slot.output, frame: frame) { index in
                    let modulationIndex = parameter.automationRate == .kRate ? 0 : index
                    let modulation = slot.paramInput.map { $0.channelData(0)[modulationIndex] } ?? 0
                    return parameter.computedValue(
                        at: frame + UInt64(index),
                        quantumStart: frame,
                        modulation: modulation
                    )
                }
            case let .oscillator(state, ended, wave, sampleRate, startTime, stopTime, frequency, detune, _):
                mixParamInputs(of: slot)
                let nyquist = sampleRate / 2
                state.render(
                    into: slot.output, frame: frame, sampleRate: sampleRate, wave: wave,
                    startTime: startTime, stopTime: stopTime, ended: ended
                ) { index in
                    // A compound parameter: each value is clamped only once
                    // combined.
                    let frequency = Self.paramComputedValue(frequency, slot.paramInputs[0], index: index, frame: frame)
                    let detune = Self.paramComputedValue(detune, slot.paramInputs[1], index: index, frame: frame)
                    let computed = frequency * exp2(detune / 1200)
                    return computed.isNaN ? 0 : min(max(computed, -nyquist), nyquist)
                }
            case let .bufferSource(state, ended, sampleRate, schedule, playbackRate, detune, _):
                mixParamInputs(of: slot)
                // A compound parameter of unbounded range, k-rate.
                let rate = Self.paramComputedValue(playbackRate, slot.paramInputs[0], index: 0, frame: frame)
                let cents = Self.paramComputedValue(detune, slot.paramInputs[1], index: 0, frame: frame)
                let computed = Double(rate) * exp2(Double(cents) / 1200)
                state.render(
                    into: slot.output, frame: frame, sampleRate: sampleRate, schedule: schedule,
                    playbackRate: computed.isNaN ? 0 : computed, ended: ended
                )
            case let .biquad(state, type, sampleRate, parameters, _):
                mixParamInputs(of: slot)
                guard let input = slot.input else { continue }
                let nyquist = Double(sampleRate) / 2
                state.render(input: input, output: slot.output, type: type, sampleRate: sampleRate) { index in
                    // Frequency and detune are a compound parameter, clamped
                    // only once combined; Q and gain are simple ones.
                    let frequency = Self.paramComputedValue(parameters[0], slot.paramInputs[0], index: index, frame: frame)
                    let detune = Self.paramComputedValue(parameters[1], slot.paramInputs[1], index: index, frame: frame)
                    let computed = Double(frequency) * exp2(Double(detune) / 1200)
                    let q = Self.computedValue(parameters[2], slot.paramInputs[2], index: index, frame: frame)
                    let gain = Self.computedValue(parameters[3], slot.paramInputs[3], index: index, frame: frame)
                    return (computed.isNaN ? 0 : min(max(computed, 0), nyquist), Double(q), Double(gain))
                }
            case let .waveShaper(state, curve, oversample):
                if let input = slot.input {
                    state.render(input: input, output: slot.output, curve: curve, oversample: oversample)
                }
            case let .constant(startFrame, stopFrame, ended, parameter, _):
                guard let startFrame else { continue }
                mixParamInputs(of: slot)
                if let stopFrame, frame + UInt64(slot.output.frameCount) > stopFrame {
                    ended.signal()
                }

                let samples = slot.output.channelData(0)
                for index in samples.indices {
                    let currentFrame = frame + UInt64(index)
                    guard currentFrame >= startFrame, stopFrame.map({ currentFrame < $0 }) ?? true else {
                        continue
                    }
                    let modulationIndex = parameter.automationRate == .kRate ? 0 : index
                    let modulation = slot.paramInput.map { $0.channelData(0)[modulationIndex] } ?? 0
                    samples[index] = parameter.computedValue(
                        at: currentFrame,
                        quantumStart: frame,
                        modulation: modulation
                    )
                }
            case let .delay(state, parameter, _):
                mixParamInputs(of: slot)
                if let input = slot.input {
                    if configuration.isCycleBreaker {
                        state.read(output: slot.output, parameter: parameter,
                                   modulation: slot.paramInput, interpretation: configuration.interpretation,
                                   frame: frame)
                    } else {
                        state.render(input: input, output: slot.output, parameter: parameter,
                                     modulation: slot.paramInput, interpretation: configuration.interpretation,
                                     frame: frame)
                    }
                }
            }
        }

        for slot in slots where slot.configuration.isCycleBreaker && !slot.configuration.isMuted {
            guard let input = slot.input, case let .delay(state, _, _) = slot.configuration.processor else { continue }
            configureInput(input, for: slot.configuration)
            input.clear()
            for sourceIndex in slot.configuration.sources {
                ChannelMixer.mix(slots[sourceIndex].output, into: input,
                                 interpretation: slot.configuration.interpretation)
            }
            state.write(input: input, frame: frame)
        }

        // Once every input, a cycle breaker's too, is mixed.
        for slot in slots {
            slot.configuration.sounding?.update(input: slot.input, output: slot.output)
        }

        let destination = slots[destinationIndex].output
        for channel in 0 ..< destination.channelCount {
            let channelTarget = target.channelData(channel)
            let source = destination.channelData(channel)
            for sample in 0 ..< frameCount {
                channelTarget[offset + sample] = source[sample]
            }
        }
    }

    // Mixes what is connected to each of the slot's parameters into its
    // parameter inputs.
    private func mixParamInputs(of slot: Slot) {
        for (paramInput, sources) in zip(slot.paramInputs, Slot.paramSources(slot.configuration.processor)) {
            guard let paramInput else { continue }
            paramInput.clear()
            for sourceIndex in sources {
                ChannelMixer.mix(slots[sourceIndex].output, into: paramInput, interpretation: .speakers)
            }
        }
    }

    private static func computedValue(
        _ parameter: AudioParamTimeline,
        _ input: AudioRenderQuantum?,
        index: Int,
        frame: UInt64
    ) -> Float {
        let modulationIndex = parameter.automationRate == .kRate ? 0 : index
        let modulation = input.map { $0.channelData(0)[modulationIndex] } ?? 0
        return parameter.computedValue(at: frame + UInt64(index), quantumStart: frame, modulation: modulation)
    }

    private static func paramComputedValue(
        _ parameter: AudioParamTimeline,
        _ input: AudioRenderQuantum?,
        index: Int,
        frame: UInt64
    ) -> Float {
        let modulationIndex = parameter.automationRate == .kRate ? 0 : index
        let modulation = input.map { $0.channelData(0)[modulationIndex] } ?? 0
        return parameter.paramComputedValue(at: frame + UInt64(index), quantumStart: frame, modulation: modulation)
    }

    private func configureInput(_ input: AudioRenderQuantum, for configuration: NodeConfiguration) {
        var maximum = 1
        for sourceIndex in configuration.sources {
            maximum = max(maximum, slots[sourceIndex].output.channelCount)
        }
        let count: Int
        switch configuration.channelCountMode {
        case .max: count = maximum
        case .clampedMax: count = min(maximum, configuration.channelCount)
        case .explicit: count = configuration.channelCount
        }
        input.setChannelCount(count)
    }
}
#endif
