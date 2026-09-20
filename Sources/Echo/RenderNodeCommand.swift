enum RenderNodeCommand: Sendable {
    case setOscillatorType(OscillatorType)
    case start(Double)
    case stop(Double)
}
