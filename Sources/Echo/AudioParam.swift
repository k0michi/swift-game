@MainActor
public final class AudioParam {
    public var value: Float {
        get { timeline.intrinsicValue(at: context.currentTime) }
        set {
            // TODO: A Swift property setter cannot surface the RangeError for invalid or curve-overlapping values.
            timeline.setImmediately(newValue, at: context.currentTime)
            context.graphDidChange()
        }
    }
    public let defaultValue: Float
    public let minValue: Float
    public let maxValue: Float
    public var automationRate: AutomationRate {
        didSet {
            timeline.automationRate = automationRate
            context.graphDidChange()
        }
    }

    weak var owner: AudioNode?
    let context: BaseAudioContext
    private var timeline: AudioParamTimeline

    init(owner: AudioNode, defaultValue: Float, minValue: Float, maxValue: Float, automationRate: AutomationRate) {
        self.owner = owner
        context = owner.context
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.automationRate = automationRate
        timeline = AudioParamTimeline(
            defaultValue: defaultValue,
            minValue: minValue,
            maxValue: maxValue,
            sampleRate: context.sampleRate,
            automationRate: automationRate
        )
    }

    var renderTimeline: AudioParamTimeline { timeline }

    @discardableResult
    public func setValueAtTime(_ value: Float, startTime: Double) throws -> AudioParam {
        try validate(value: value, time: startTime)
        try timeline.insert(.init(time: max(startTime, context.currentTime), kind: .set(value)))
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func linearRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try validate(value: value, time: endTime)
        let time = max(endTime, context.currentTime)
        var updated = timeline
        try updated.prepareForRamp(endingAt: time, currentTime: context.currentTime)
        try updated.insert(.init(time: time, kind: .linearRamp(value)))
        timeline = updated
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func exponentialRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try validate(value: value, time: endTime)
        guard value != 0 else { throw WebAudioError.rangeError }
        let time = max(endTime, context.currentTime)
        var updated = timeline
        try updated.prepareForRamp(endingAt: time, currentTime: context.currentTime)
        try updated.insert(.init(time: time, kind: .exponentialRamp(value)))
        timeline = updated
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func setTargetAtTime(_ target: Float, startTime: Double, timeConstant: Float) throws -> AudioParam {
        try validate(value: target, time: startTime)
        guard timeConstant.isFinite, timeConstant >= 0 else { throw WebAudioError.rangeError }
        try timeline.insert(.init(
            time: max(startTime, context.currentTime),
            kind: .target(target, timeConstant: timeConstant)
        ))
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func setValueCurveAtTime(_ values: [Float], startTime: Double, duration: Double) throws -> AudioParam {
        guard values.count >= 2 else { throw WebAudioError.invalidState }
        guard values.allSatisfy(\.isFinite),
              startTime.isFinite, startTime >= 0,
              duration.isFinite, duration > 0,
              (startTime + duration).isFinite
        else {
            throw WebAudioError.rangeError
        }
        try timeline.insertCurve(values, at: max(startTime, context.currentTime), duration: duration)
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func cancelScheduledValues(_ cancelTime: Double) throws -> AudioParam {
        let time = try validatedTime(cancelTime)
        timeline.cancel(from: time)
        context.graphDidChange()
        return self
    }

    @discardableResult
    public func cancelAndHoldAtTime(_ cancelTime: Double) throws -> AudioParam {
        let time = try validatedTime(cancelTime)
        timeline.cancelAndHold(at: time)
        context.graphDidChange()
        return self
    }

    private func validate(value: Float, time: Double) throws {
        guard value.isFinite else { throw WebAudioError.rangeError }
        _ = try validatedTime(time)
    }

    private func validatedTime(_ time: Double) throws -> Double {
        guard time.isFinite, time >= 0 else { throw WebAudioError.rangeError }
        return max(time, context.currentTime)
    }

}
