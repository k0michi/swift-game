public final class AudioParam {
    public var value: Float {
        didSet { graph.setParamValue(id: id, value: value) }
    }
    public var automationRate: AutomationRate {
        didSet { graph.setAutomationRate(id: id, value: automationRate) }
    }
    public let defaultValue: Float
    public let minValue: Float
    public let maxValue: Float

    let graph: AudioGraph
    let id: AudioParamID

    init(
        graph: AudioGraph,
        defaultValue: Float,
        minValue: Float,
        maxValue: Float,
        automationRate: AutomationRate = .aRate
    ) {
        self.graph = graph
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.automationRate = automationRate
        value = defaultValue
        id = graph.registerParam(
            defaultValue: defaultValue,
            minValue: minValue,
            maxValue: maxValue,
            automationRate: automationRate
        )
    }

    @discardableResult
    public func setValueAtTime(_ value: Float, startTime: Double) -> AudioParam {
        self.value = value
        return self
    }

    @discardableResult
    public func linearRampToValueAtTime(_ value: Float, endTime: Double) -> AudioParam {
        self.value = value
        return self
    }

    @discardableResult
    public func exponentialRampToValueAtTime(_ value: Float, endTime: Double) -> AudioParam {
        self.value = value
        return self
    }

    @discardableResult
    public func setTargetAtTime(_ target: Float, startTime: Double, timeConstant: Float) -> AudioParam {
        value = target
        return self
    }

    @discardableResult
    public func setValueCurveAtTime(_ values: [Float], startTime: Double, duration: Double) -> AudioParam {
        if let last = values.last { value = last }
        return self
    }

    @discardableResult
    public func cancelScheduledValues(_ cancelTime: Double) -> AudioParam { self }

    @discardableResult
    public func cancelAndHoldAtTime(_ cancelTime: Double) -> AudioParam { self }
}
