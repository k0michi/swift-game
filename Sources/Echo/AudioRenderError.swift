public enum AudioRenderError: Error, Equatable {
    case invalidFrameCount(Int)
    case insufficientOutputChannels(required: Int, actual: Int)
}
