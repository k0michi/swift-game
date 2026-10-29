// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// What a parameter is inside its context: its timeline, which renders take a
// copy of. Its node's handler keeps it.
@MainActor
final class AudioParamHandler {
    var value: Float {
        get { timeline.intrinsicValue(at: context.currentTime) }
        set {
            // TODO: A Swift property setter cannot surface the RangeError for invalid or curve-overlapping values.
            discardPastEvents()
            timeline.setImmediately(newValue, at: context.currentTime)
            context.graphDidChange()
        }
    }
    let defaultValue: Float
    let minValue: Float
    let maxValue: Float
    var automationRate: AutomationRate {
        didSet {
            // TODO: A Swift property setter cannot surface the InvalidStateError for a fixed rate, which stays.
            guard !isAutomationRateFixed else {
                automationRate = oldValue
                return
            }
            timeline.automationRate = automationRate
            context.graphDidChange()
        }
    }

    // Its node's handler, which keeps it.
    unowned let owner: AudioHandler
    unowned let context: BaseAudioContext
    // The parameter the caller holds, while the caller keeps it.
    weak var handle: AudioParam?
    private var timeline: AudioParamTimeline
    // Whether the parameter has automation rate constraints, which keep its
    // rate from changing.
    private let isAutomationRateFixed: Bool

    init(
        owner: AudioHandler,
        defaultValue: Float,
        minValue: Float,
        maxValue: Float,
        automationRate: AutomationRate,
        isAutomationRateFixed: Bool = false
    ) {
        self.isAutomationRateFixed = isAutomationRateFixed
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

    func setValueAtTime(_ value: Float, startTime: Double) throws {
        discardPastEvents()
        try validate(value: value, time: startTime)
        try timeline.insert(.init(time: max(startTime, context.currentTime), kind: .set(value)))
        context.graphDidChange()
    }

    func linearRampToValueAtTime(_ value: Float, endTime: Double) throws {
        discardPastEvents()
        try validate(value: value, time: endTime)
        let time = max(endTime, context.currentTime)
        var updated = timeline
        try updated.prepareForRamp(endingAt: time, currentTime: context.currentTime)
        try updated.insert(.init(time: time, kind: .linearRamp(value)))
        timeline = updated
        context.graphDidChange()
    }

    func exponentialRampToValueAtTime(_ value: Float, endTime: Double) throws {
        discardPastEvents()
        try validate(value: value, time: endTime)
        guard value != 0 else { throw WebAudioError.rangeError }
        let time = max(endTime, context.currentTime)
        var updated = timeline
        try updated.prepareForRamp(endingAt: time, currentTime: context.currentTime)
        try updated.insert(.init(time: time, kind: .exponentialRamp(value)))
        timeline = updated
        context.graphDidChange()
    }

    func setTargetAtTime(_ target: Float, startTime: Double, timeConstant: Float) throws {
        discardPastEvents()
        try validate(value: target, time: startTime)
        guard timeConstant.isFinite, timeConstant >= 0 else { throw WebAudioError.rangeError }
        try timeline.insert(.init(
            time: max(startTime, context.currentTime),
            kind: .target(target, timeConstant: timeConstant)
        ))
        context.graphDidChange()
    }

    func setValueCurveAtTime(_ values: [Float], startTime: Double, duration: Double) throws {
        discardPastEvents()
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
    }

    func cancelScheduledValues(_ cancelTime: Double) throws {
        discardPastEvents()
        let time = try validatedTime(cancelTime)
        timeline.cancel(from: time)
        context.graphDidChange()
    }

    func cancelAndHoldAtTime(_ cancelTime: Double) throws {
        discardPastEvents()
        let time = try validatedTime(cancelTime)
        timeline.cancelAndHold(at: time)
        context.graphDidChange()
    }

    // Before each change, so that the timeline holds little more than the
    // changes still to come, however many came before.
    private func discardPastEvents() {
        timeline.discardEvents(before: context.currentTime)
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

// The parameter the caller holds, which keeps its node's handler, and so
// keeps it in its context, and forwards to its handler.
@MainActor
public final class AudioParam {
    let handler: AudioParamHandler
    private let owner: AudioHandler
    private let context: BaseAudioContext

    init(_ handler: AudioParamHandler) {
        self.handler = handler
        owner = handler.owner
        context = handler.context
        handler.handle = self
    }

    public var value: Float {
        get { handler.value }
        set { handler.value = newValue }
    }
    public var defaultValue: Float { handler.defaultValue }
    public var minValue: Float { handler.minValue }
    public var maxValue: Float { handler.maxValue }
    public var automationRate: AutomationRate {
        get { handler.automationRate }
        set { handler.automationRate = newValue }
    }

    @discardableResult
    public func setValueAtTime(_ value: Float, startTime: Double) throws -> AudioParam {
        try handler.setValueAtTime(value, startTime: startTime)
        return self
    }

    @discardableResult
    public func linearRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try handler.linearRampToValueAtTime(value, endTime: endTime)
        return self
    }

    @discardableResult
    public func exponentialRampToValueAtTime(_ value: Float, endTime: Double) throws -> AudioParam {
        try handler.exponentialRampToValueAtTime(value, endTime: endTime)
        return self
    }

    @discardableResult
    public func setTargetAtTime(_ target: Float, startTime: Double, timeConstant: Float) throws -> AudioParam {
        try handler.setTargetAtTime(target, startTime: startTime, timeConstant: timeConstant)
        return self
    }

    @discardableResult
    public func setValueCurveAtTime(_ values: [Float], startTime: Double, duration: Double) throws -> AudioParam {
        try handler.setValueCurveAtTime(values, startTime: startTime, duration: duration)
        return self
    }

    @discardableResult
    public func cancelScheduledValues(_ cancelTime: Double) throws -> AudioParam {
        try handler.cancelScheduledValues(cancelTime)
        return self
    }

    @discardableResult
    public func cancelAndHoldAtTime(_ cancelTime: Double) throws -> AudioParam {
        try handler.cancelAndHoldAtTime(cancelTime)
        return self
    }
}
#endif
