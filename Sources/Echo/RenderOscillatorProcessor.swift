import Foundation

final class RenderOscillatorProcessor: @unchecked Sendable, RenderNodeProcessor {
    private let frequency: AudioParamID
    private let detune: AudioParamID
    private var type: OscillatorType
    private var phase: Double = 0
    private var startTime: Double?
    private var stopTime: Double?

    init(frequency: AudioParamID, detune: AudioParamID, type: OscillatorType) {
        self.frequency = frequency
        self.detune = detune
        self.type = type
    }

    var parameterIDs: [AudioParamID] { [frequency, detune] }

    func outputChannelCount(inputChannelCount _: Int, node _: RenderNodeState) -> Int {
        1
    }

    func apply(_ command: RenderNodeCommand) {
        switch command {
        case .setOscillatorType(let type):
            self.type = type
        case .start(let when):
            startTime = when
        case .stop(let when):
            stopTime = when
        }
    }

    func process(
        context: RenderProcessContext,
        input _: AudioBus,
        output: inout AudioBus
    ) {
        guard let startTime else { return }
        let quantumStartTime = Double(context.currentFrame) / Double(context.sampleRate)
        let frequency = Double(context.params[frequency]?.value ?? 440)
        let detune = Double(context.params[detune]?.value ?? 0)
        let phaseIncrement = 2 * Double.pi * frequency * pow(2, detune / 1_200)
            / Double(context.sampleRate)

        for frame in 0..<context.frameCount {
            let time = quantumStartTime + Double(frame) / Double(context.sampleRate)
            guard time >= startTime, stopTime.map({ time < $0 }) ?? true else { continue }
            output[0, frame] = sample(phase: phase)
            phase = (phase + phaseIncrement).truncatingRemainder(dividingBy: 2 * Double.pi)
            if phase < 0 { phase += 2 * Double.pi }
        }
    }

    private func sample(phase: Double) -> Float {
        switch type {
        case .sine:
            return Float(sin(phase))
        case .square:
            return phase < Double.pi ? 1 : -1
        case .sawtooth:
            return Float(phase / Double.pi - 1)
        case .triangle:
            return Float(2 * abs(2 * (phase / (2 * Double.pi)) - 1) - 1)
        case .custom:
            // TODO: Render the oscillator's PeriodicWave.
            return 0
        }
    }
}
