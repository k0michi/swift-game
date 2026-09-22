struct OfflineRenderTarget: @unchecked Sendable {
    let channelCount: Int
    let length: Int
    private let channels: [UnsafeMutableBufferPointer<Float>]

    init(buffer: AudioBuffer, plan: AudioRenderPlan) throws {
        guard plan.frameCount > 0,
              Int(buffer.length).isMultiple(of: plan.frameCount),
              Int(buffer.numberOfChannels) == plan.destinationChannelCount
        else {
            throw WebAudioError.notSupported
        }
        channelCount = Int(buffer.numberOfChannels)
        length = Int(buffer.length)
        channels = try (0 ..< buffer.numberOfChannels).map { try buffer.getChannelData($0) }
    }

    func channelData(_ channel: Int) -> UnsafeMutableBufferPointer<Float> {
        channels[channel]
    }
}
