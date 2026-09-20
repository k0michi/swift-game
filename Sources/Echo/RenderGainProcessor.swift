final class RenderGainProcessor: RenderNodeProcessor {
    private let gain: AudioParamID

    init(gain: AudioParamID) {
        self.gain = gain
    }

    var parameterIDs: [AudioParamID] { [gain] }

    func outputChannelCount(
        output _: Int,
        inputChannelCounts: [Int],
        node _: RenderNodeState
    ) -> Int {
        inputChannelCounts.first ?? 1
    }

    func process(
        context: RenderProcessContext,
        inputs: [AudioBus],
        outputs: inout [AudioBus]
    ) {
        guard let input = inputs.first, !outputs.isEmpty else { return }
        let values = context.parameterValues[gain] ?? Array(repeating: 1, count: context.frameCount)
        for channel in 0..<outputs[0].numberOfChannels {
            for frame in 0..<context.frameCount {
                outputs[0][channel, frame] = input[channel, frame] * values[frame]
            }
        }
    }
}
