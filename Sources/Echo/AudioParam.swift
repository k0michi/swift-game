@MainActor
public final class AudioParam {
    public var value: Float {
        didSet { context.graphDidChange() }
    }
    public let defaultValue: Float
    public let minValue: Float
    public let maxValue: Float
    public let automationRate: AutomationRate

    weak var owner: AudioNode?
    let context: BaseAudioContext

    init(owner: AudioNode, defaultValue: Float, minValue: Float, maxValue: Float, automationRate: AutomationRate) {
        self.owner = owner
        context = owner.context
        self.defaultValue = defaultValue
        value = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.automationRate = automationRate
    }

    // TODO: Implement the full AudioParam automation event timeline.
}
