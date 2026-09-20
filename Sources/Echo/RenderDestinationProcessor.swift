final class RenderDestinationProcessor: RenderNodeProcessor {
    func outputChannelCount(
        output _: Int,
        inputChannelCounts _: [Int],
        node: RenderNodeState
    ) -> Int {
        Int(node.channelCount)
    }

    func process(
        context: RenderProcessContext,
        inputs: [AudioBus],
        outputs: inout [AudioBus]
    ) {
        guard let input = inputs.first, !outputs.isEmpty else { return }
        for channel in 0..<min(input.numberOfChannels, outputs[0].numberOfChannels) {
            for frame in 0..<context.frameCount {
                outputs[0][channel, frame] = input[channel, frame]
            }
        }
    }
}
