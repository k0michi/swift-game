final class RenderGainProcessor: RenderNodeProcessor {
    private let gain: AudioParamID

    init(gain: AudioParamID) {
        self.gain = gain
    }

    var parameterIDs: [AudioParamID] { [gain] }

    func outputChannelCount(inputChannelCount: Int, node _: RenderNodeState) -> Int {
        inputChannelCount
    }

    func process(
        context: RenderProcessContext,
        input: AudioBus,
        output: inout AudioBus
    ) {
        let gain = context.params[gain]?.value ?? 1
        for channel in 0..<output.numberOfChannels {
            for frame in 0..<context.frameCount {
                output[channel, frame] = input[channel, frame] * gain
            }
        }
    }
}
