struct RenderParamState: Sendable {
    let id: AudioParamID
    var value: Float
    let defaultValue: Float
    let minValue: Float
    let maxValue: Float
    var automationRate: AutomationRate
}
