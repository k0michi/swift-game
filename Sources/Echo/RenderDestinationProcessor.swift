final class RenderDestinationProcessor: RenderNodeProcessor {
    func outputChannelCount(inputChannelCount _: Int, node: RenderNodeState) -> Int {
        Int(node.channelCount)
    }

    func process(
        context: RenderProcessContext,
        input: AudioBus,
        output: inout AudioBus
    ) {
        for channel in 0..<min(input.numberOfChannels, output.numberOfChannels) {
            for frame in 0..<context.frameCount {
                output[channel, frame] = input[channel, frame]
            }
        }
    }
}
