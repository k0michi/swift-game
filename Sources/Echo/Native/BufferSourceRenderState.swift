// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
// An AudioBufferSourceNode's playback, following the specification's
// algorithm, whose state carries from one render quantum and render plan to
// the next. Used only by the rendering thread.
final class BufferSourceRenderState: @unchecked Sendable {
    // What the node schedules and sets, updated each render quantum.
    struct Schedule: Sendable {
        var content: BufferSourceContent?
        var start: Double?
        var stop: Double?
        var offset: Double
        var duration: Double?
        var loop: Bool
        var loopStart: Double
        var loopEnd: Double
    }

    // The playhead, in seconds of the buffer.
    private var bufferTime = 0.0
    private var bufferTimeElapsed = 0.0
    private var playbackOffset = 0.0
    private var started = false
    private var enteredLoop = false
    private var hasEnded = false
    // A stop the node forces: a null buffer stops it for good.
    private var forcedStop = Double.infinity

    // `playbackRate` is the computedPlaybackRate for the quantum.
    func render(
        into output: AudioRenderQuantum,
        frame: UInt64,
        sampleRate: Float,
        schedule: Schedule,
        playbackRate: Double,
        ended: EndedSignal
    ) {
        // Once ended, the output is a single channel of silence.
        guard !hasEnded else {
            output.setChannelCount(1)
            return
        }
        output.setChannelCount(schedule.content?.channels.count ?? 1)
        // The plan cleared only the channels the output had before.
        output.clear()
        guard let start = schedule.start else { return }

        let sampleRate = Double(sampleRate)
        let dt = 1 / sampleRate
        let currentTime = Double(frame) / sampleRate
        let duration = schedule.duration ?? .infinity

        var loopRange = 0.0 ..< 0.0
        if schedule.loop, let content = schedule.content {
            loopRange = Self.loopRange(schedule, bufferDuration: content.duration)
        } else {
            enteredLoop = false
        }
        guard let content = schedule.content else {
            forcedStop = min(forcedStop, currentTime)
            finish(at: currentTime + Double(output.frameCount) * dt, schedule: schedule, ended: ended)
            return
        }
        let stop = min(schedule.stop ?? .infinity, forcedStop)

        for index in 0 ..< output.frameCount {
            let time = Double(frame + UInt64(index)) / sampleRate
            guard time >= start, time < stop, bufferTimeElapsed < duration else { continue }
            if !started {
                // The offset is clamped to the buffer when the start is
                // reached, and to the loop when playing toward it.
                var offset = min(schedule.offset, content.duration)
                if schedule.loop, playbackRate >= 0, offset >= loopRange.upperBound {
                    offset = loopRange.upperBound
                }
                if playbackRate < 0, schedule.loop, offset < loopRange.lowerBound {
                    offset = loopRange.lowerBound
                }
                playbackOffset = offset
                bufferTime = offset
                started = true
            }
            if schedule.loop {
                if !enteredLoop {
                    if playbackOffset < loopRange.upperBound, bufferTime >= loopRange.lowerBound {
                        enteredLoop = true
                    }
                    if playbackOffset >= loopRange.upperBound, bufferTime < loopRange.upperBound {
                        enteredLoop = true
                    }
                }
                if enteredLoop {
                    bufferTime = Self.wrap(bufferTime, into: loopRange)
                }
            }
            if bufferTime >= 0, bufferTime < content.duration {
                let loop = schedule.loop && enteredLoop ? loopRange : nil
                for channel in 0 ..< content.channels.count {
                    output.channelData(channel)[index] = Self.signal(content, channel: channel, at: bufferTime, loop: loop)
                }
            }
            bufferTime = Self.snapped(bufferTime + dt * playbackRate, sampleRate: content.sampleRate)
            bufferTimeElapsed = Self.snapped(bufferTimeElapsed + dt * playbackRate, sampleRate: content.sampleRate)
        }

        // The source also ends once it has played the whole buffer, or for
        // its duration.
        let playedBuffer = started && !schedule.loop
            && (playbackRate > 0 ? bufferTime >= content.duration : playbackRate < 0 && bufferTime < 0)
        if playedBuffer || started && bufferTimeElapsed >= duration {
            forcedStop = min(forcedStop, currentTime)
        }
        finish(at: currentTime + Double(output.frameCount) * dt, schedule: schedule, ended: ended)
    }

    // Ends playback once the quantum reaches the stop time.
    private func finish(at endTime: Double, schedule: Schedule, ended: EndedSignal) {
        if endTime >= min(schedule.stop ?? .infinity, forcedStop) {
            hasEnded = true
            ended.signal()
        }
    }

    // A playhead position adding up frame times lands a little off the frames
    // it should reach, and then off the loop ends and durations they make.
    // A position within a millionth of a frame of one is put on it.
    private static func snapped(_ time: Double, sampleRate: Double) -> Double {
        let frame = time * sampleRate
        let nearest = frame.rounded()
        return abs(frame - nearest) < 1e-6 ? nearest / sampleRate : time
    }

    // The loop's endpoints, or the whole buffer when they do not make one
    // within it.
    private static func loopRange(_ schedule: Schedule, bufferDuration: Double) -> Range<Double> {
        if schedule.loopStart >= 0, schedule.loopEnd > 0, schedule.loopStart < schedule.loopEnd {
            let end = min(schedule.loopEnd, bufferDuration)
            // A start beyond the buffer would leave no loop to play.
            if schedule.loopStart < end {
                return schedule.loopStart ..< end
            }
        }
        return 0 ..< bufferDuration
    }

    private static func wrap(_ time: Double, into loop: Range<Double>) -> Double {
        let length = loop.upperBound - loop.lowerBound
        guard length > 0 else { return loop.lowerBound }
        if time >= loop.upperBound {
            return loop.lowerBound + (time - loop.lowerBound).truncatingRemainder(dividingBy: length)
        }
        if time < loop.lowerBound {
            let wrapped = loop.upperBound - (loop.lowerBound - time).truncatingRemainder(dividingBy: length)
            return wrapped >= loop.upperBound ? loop.lowerBound : wrapped
        }
        return time
    }

    // The playback signal at a playhead position: a sample frame where there
    // is one, and otherwise the line between the frames on either side. Past
    // the loop's end, the next frame is the loop's start.
    private static func signal(
        _ content: BufferSourceContent,
        channel: Int,
        at position: Double,
        loop: Range<Double>?
    ) -> Float {
        var frame = position * content.sampleRate
        // Positions reached by adding up frame times land a little off them.
        if abs(frame - frame.rounded()) < 1e-9 {
            frame = frame.rounded()
        }
        let index = Int(frame)
        let fraction = Float(frame - Double(index))
        let samples = content.channels[channel]
        let current = index < samples.count ? samples[index] : 0
        guard fraction > 0 else { return current }
        var nextIndex = index + 1
        if let loop, Double(nextIndex) >= loop.upperBound * content.sampleRate {
            nextIndex -= Int(((loop.upperBound - loop.lowerBound) * content.sampleRate).rounded())
        }
        let next = (0 ..< samples.count).contains(nextIndex) ? samples[nextIndex] : 0
        return current + fraction * (next - current)
    }
}
#endif
