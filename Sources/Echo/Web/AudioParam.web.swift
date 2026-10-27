#if os(Emscripten)
@MainActor
public final class AudioParam {
    public var value: Float {
        get { Float(object.number("value")) }
        // TODO: A Swift property setter cannot surface the RangeError for invalid or curve-overlapping values.
        set { try? object.set("value", Double(newValue)) }
    }
    public let defaultValue: Float
    public let minValue: Float
    public let maxValue: Float
    public var automationRate: AutomationRate {
        get { AutomationRate(rawValue: object.string("automationRate"))! }
        // The browser throws for parameters whose rate is fixed; Echo's own
        // parameters accept either.
        set { try? object.set("automationRate", newValue.rawValue) }
    }

    let context: BaseAudioContext
    let object: JSObjectReference

    init(context: BaseAudioContext, object: JSObjectReference) {
        self.context = context
        self.object = object
        defaultValue = Float(object.number("defaultValue"))
        minValue = Float(object.number("minValue"))
        maxValue = Float(object.number("maxValue"))
    }

    @discardableResult
    public func setValueAtTime(_ value: Float, startTime: Double) throws -> AudioParam {
        try object.call("setValueAtTime", nil, [Double(value), startTime])
        return self
    }

    @discardableResult
    public func linearRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try object.call("linearRampToValueAtTime", nil, [Double(value), endTime])
        return self
    }

    @discardableResult
    public func exponentialRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try object.call("exponentialRampToValueAtTime", nil, [Double(value), endTime])
        return self
    }

    @discardableResult
    public func setTargetAtTime(_ target: Float, startTime: Double, timeConstant: Float) throws -> AudioParam {
        try object.call("setTargetAtTime", nil, [Double(target), startTime, Double(timeConstant)])
        return self
    }

    @discardableResult
    public func setValueCurveAtTime(_ values: [Float], startTime: Double, duration: Double) throws -> AudioParam {
        try object.call("setValueCurveAtTime", floats: values, [startTime, duration])
        return self
    }

    @discardableResult
    public func cancelScheduledValues(_ cancelTime: Double) throws -> AudioParam {
        try object.call("cancelScheduledValues", nil, [cancelTime])
        return self
    }

    @discardableResult
    public func cancelAndHoldAtTime(_ cancelTime: Double) throws -> AudioParam {
        try object.call("cancelAndHoldAtTime", nil, [cancelTime])
        return self
    }
}
#endif
