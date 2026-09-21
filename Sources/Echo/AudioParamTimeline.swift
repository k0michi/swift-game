import Foundation

struct AudioParamTimeline: Sendable {
    struct Event: Sendable {
        enum Kind: Sendable {
            case set(Float)
            case linearRamp(Float)
            case exponentialRamp(Float)
            case target(Float, timeConstant: Float)
            case curve([Float], duration: Double, cutoff: Double?)
        }

        let time: Double
        let kind: Kind
    }

    let defaultValue: Float
    let minValue: Float
    let maxValue: Float
    let sampleRate: Float
    var automationRate: AutomationRate
    private(set) var events: [Event] = []

    mutating func setImmediately(_ value: Float, at time: Double) {
        for index in events.indices {
            if case let .curve(values, duration, cutoff) = events[index].kind,
               events[index].time <= time,
               time < min(events[index].time + duration, cutoff ?? .infinity) {
                events[index] = Event(
                    time: events[index].time,
                    kind: .curve(values, duration: duration, cutoff: time)
                )
            }
        }
        let index = events.firstIndex { $0.time > time } ?? events.endIndex
        events.insert(Event(time: time, kind: .set(value)), at: index)
    }

    mutating func insert(_ event: Event) throws {
        guard !events.contains(where: { existing in
            if case let .curve(_, duration, cutoff) = existing.kind {
                return event.time >= existing.time && event.time < min(existing.time + duration, cutoff ?? .infinity)
            }
            return false
        }) else {
            throw WebAudioError.notSupported
        }
        let index = events.firstIndex { $0.time > event.time } ?? events.endIndex
        events.insert(event, at: index)
    }

    mutating func insertCurve(_ values: [Float], at time: Double, duration: Double) throws {
        let end = time + duration
        guard !events.contains(where: { $0.time > time && $0.time < end }),
              !events.contains(where: { existing in
                  if case let .curve(_, existingDuration, cutoff) = existing.kind {
                      return time < min(existing.time + existingDuration, cutoff ?? .infinity)
                          && end > existing.time
                  }
                  return false
              })
        else {
            throw WebAudioError.notSupported
        }
        let index = events.firstIndex { $0.time > time } ?? events.endIndex
        events.insert(Event(time: time, kind: .curve(values, duration: duration, cutoff: nil)), at: index)
    }

    mutating func prepareForRamp(endingAt endTime: Double, currentTime: Double) throws {
        guard let precedingIndex = events.lastIndex(where: { $0.time <= endTime }) else {
            try insert(Event(time: currentTime, kind: .set(intrinsicValue(at: currentTime))))
            return
        }
        let preceding = events[precedingIndex]
        guard case .target = preceding.kind else { return }
        if preceding.time >= currentTime {
            let initial = intrinsicValue(at: preceding.time)
            events[precedingIndex] = Event(time: preceding.time, kind: .set(initial))
        } else {
            let initial = intrinsicValue(at: currentTime)
            try insert(Event(time: currentTime, kind: .set(initial)))
        }
    }

    mutating func cancel(from time: Double) {
        let activeTargetIndex = events.lastIndex(where: { $0.time < time }).flatMap { index -> Int? in
            if case .target = events[index].kind { return index }
            return nil
        }
        let valueBeforeTarget = activeTargetIndex.map { index -> Float in
            var preceding = self
            preceding.events = Array(events[..<index])
            return preceding.intrinsicValue(at: events[index].time)
        }
        events = events.compactMap { event in
            if case let .curve(_, duration, cutoff) = event.kind {
                return min(event.time + duration, cutoff ?? .infinity) >= time ? nil : event
            }
            return event.time >= time ? nil : event
        }
        if let valueBeforeTarget {
            events.append(Event(time: time, kind: .set(valueBeforeTarget)))
        }
    }

    mutating func cancelAndHold(at time: Double) {
        let heldValue = intrinsicValue(at: time)
        let nextEvent = events.first { $0.time > time }
        let previousEvent = events.last { $0.time <= time }
        let activeCurveIndex = events.firstIndex { event in
            if case let .curve(_, duration, cutoff) = event.kind {
                return event.time <= time && time < min(event.time + duration, cutoff ?? .infinity)
            }
            return false
        }

        let activeCurve = activeCurveIndex.map { events[$0] }
        events.removeAll { $0.time >= time }
        if let activeCurve,
           let survivingIndex = events.firstIndex(where: { $0.time == activeCurve.time }),
           case let .curve(values, duration, _) = activeCurve.kind {
            events[survivingIndex] = Event(
                time: activeCurve.time,
                kind: .curve(values, duration: duration, cutoff: time)
            )
        }
        if let nextEvent, activeCurveIndex == nil {
            let kind: Event.Kind
            if let previousEvent, case .target = previousEvent.kind {
                kind = .set(heldValue)
            } else {
                switch nextEvent.kind {
                case .linearRamp: kind = .linearRamp(heldValue)
                case .exponentialRamp: kind = .exponentialRamp(heldValue)
                default: kind = .set(heldValue)
                }
            }
            events.append(Event(time: time, kind: kind))
        } else {
            events.append(Event(time: time, kind: .set(heldValue)))
        }
    }

    func computedValue(at frame: UInt64, quantumStart: UInt64, modulation: Float) -> Float {
        let selectedFrame = automationRate == .kRate ? quantumStart : frame
        let intrinsic = intrinsicValue(at: Double(selectedFrame) / Double(sampleRate))
        let sum = intrinsic + modulation
        return min(max(sum.isNaN ? defaultValue : sum, minValue), maxValue)
    }

    func intrinsicValue(at time: Double) -> Float {
        var anchorTime = 0.0
        var anchorValue = defaultValue
        var target: (value: Float, initial: Float, start: Double, timeConstant: Float)?

        for event in events {
            if time < event.time {
                switch event.kind {
                case let .linearRamp(endValue):
                    return linear(anchorValue, endValue, from: anchorTime, to: event.time, at: time)
                case let .exponentialRamp(endValue):
                    return exponential(anchorValue, endValue, from: anchorTime, to: event.time, at: time)
                default:
                    return target.map { targetValue($0, at: time) } ?? anchorValue
                }
            }

            if let target {
                anchorValue = targetValue(target, at: event.time)
                anchorTime = event.time
            }

            switch event.kind {
            case let .set(value), let .linearRamp(value), let .exponentialRamp(value):
                anchorValue = value
                anchorTime = event.time
                target = nil
            case let .target(value, timeConstant):
                target = (value, anchorValue, event.time, timeConstant)
                anchorTime = event.time
            case let .curve(values, duration, cutoff):
                let end = min(event.time + duration, cutoff ?? .infinity)
                if time < end {
                    return curveValue(values, from: event.time, duration: duration, at: time)
                }
                anchorValue = curveValue(values, from: event.time, duration: duration, at: end)
                anchorTime = end
                target = nil
            }
        }
        return target.map { targetValue($0, at: time) } ?? anchorValue
    }

    private func linear(_ first: Float, _ last: Float, from start: Double, to end: Double, at time: Double) -> Float {
        guard end > start else { return last }
        return Float(Double(first) + (Double(last) - Double(first)) * (time - start) / (end - start))
    }

    private func exponential(_ first: Float, _ last: Float, from start: Double, to end: Double, at time: Double) -> Float {
        guard end > start else { return last }
        guard first != 0, last != 0, first.sign == last.sign else { return first }
        return Float(Double(first) * pow(Double(last) / Double(first), (time - start) / (end - start)))
    }

    private func targetValue(
        _ target: (value: Float, initial: Float, start: Double, timeConstant: Float),
        at time: Double
    ) -> Float {
        guard target.timeConstant > 0 else { return target.value }
        return Float(Double(target.value) + (Double(target.initial) - Double(target.value))
            * exp(-(time - target.start) / Double(target.timeConstant)))
    }

    private func curveValue(_ values: [Float], from start: Double, duration: Double, at time: Double) -> Float {
        let position = min(max((time - start) / duration, 0), 1) * Double(values.count - 1)
        let index = min(Int(position), values.count - 2)
        let fraction = Float(position - Double(index))
        return values[index] * (1 - fraction) + values[index + 1] * fraction
    }
}
