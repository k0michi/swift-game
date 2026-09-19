public enum AudioGraphError: Error, Equatable {
    case differentContext
    case invalidInput(UInt32)
    case invalidOutput(UInt32)
}
