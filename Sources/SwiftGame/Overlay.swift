/// Recent frame intervals for the profiler-style graph, oldest first from `next`.
struct FrameGraph {
    static let capacity = 240
    static let barWidth: Float = 2
    static let pixelsPerMillisecond: Float = 3
    static let maxMilliseconds: Float = 50

    var samples = [Float](repeating: 0, count: capacity)
    var next = 0

    mutating func record(_ milliseconds: Float) {
        samples[next] = milliseconds
        next = (next + 1) % Self.capacity
    }

    // Draws the frame intervals as bars in the bottom-right corner, like the
    // Minecraft profiler: green up to 60 FPS, yellow up to 30 FPS, red beyond.
    // Thin lines mark 16.7 ms (60 FPS) and 33.3 ms (30 FPS).
    func append(to batch: inout Batch) {
        let width = Float(Self.capacity) * Self.barWidth
        let left = fieldWidth - width
        let bottom = fieldHeight
        let height = Self.maxMilliseconds * Self.pixelsPerMillisecond

        batch.appendRect(
            left: left, top: bottom - height, right: left + width, bottom: bottom,
            color: RGBA(r: 0, g: 0, b: 0, a: 0.45))

        for offset in 0..<Self.capacity {
            let milliseconds = samples[(next + offset) % Self.capacity]
            guard milliseconds > 0 else { continue }
            let barLeft = left + Float(offset) * Self.barWidth
            let barHeight = min(milliseconds, Self.maxMilliseconds) * Self.pixelsPerMillisecond
            let color =
                if milliseconds <= 1000.0 / 60 + 1 {
                    RGBA(r: 0.3, g: 0.9, b: 0.3, a: 1)
                } else if milliseconds <= 1000.0 / 30 + 1 {
                    RGBA(r: 0.95, g: 0.85, b: 0.2, a: 1)
                } else {
                    RGBA(r: 0.95, g: 0.25, b: 0.2, a: 1)
                }
            batch.appendRect(
                left: barLeft, top: bottom - barHeight, right: barLeft + Self.barWidth,
                bottom: bottom, color: color)
        }

        for milliseconds: Float in [1000.0 / 60, 1000.0 / 30] {
            let y = bottom - milliseconds * Self.pixelsPerMillisecond
            batch.appendRect(
                left: left, top: y - 0.5, right: left + width, bottom: y + 0.5,
                color: RGBA(r: 1, g: 1, b: 1, a: 0.6))
        }
    }
}

/// Frames per second, averaged over half a second so the number is readable.
struct FPSCounter {
    static let interval: Float = 500

    var frames = 0
    var milliseconds: Float = 0
    var text = "--.- FPS"

    mutating func record(_ frameMilliseconds: Float) {
        frames += 1
        milliseconds += frameMilliseconds
        guard milliseconds >= Self.interval else { return }
        let fps = Float(frames) * 1000 / milliseconds
        text = "\(formatTenths(fps)) FPS  \(formatTenths(milliseconds / Float(frames))) ms"
        frames = 0
        milliseconds = 0
    }

    // Draws the FPS in the top-left corner with the dot font, and what was
    // built in smaller dots under it, over a dark backdrop and with a
    // shadow so they stay readable on any background.
    func append(to batch: inout Batch) {
        let lines: [(text: String, scale: Float)] = [(text, 2), (BuildInfo.version, 1)]
        let padding: Float = 4
        let lineSpacing: Float = 3

        let width = lines.map { BitmapFont.width(of: $0.text, scale: $0.scale) }.max() ?? 0
        let height = lines.map { Float(BitmapFont.glyphHeight) * $0.scale }.reduce(0, +)
            + lineSpacing * Float(lines.count - 1)
        batch.appendRect(
            left: 0, top: 0, right: width + padding * 2, bottom: height + padding * 2,
            color: RGBA(r: 0, g: 0, b: 0, a: 0.45))
        var top = padding
        for (text, scale) in lines {
            BitmapFont.appendText(
                text, x: padding + scale / 2, y: top + scale / 2, scale: scale,
                color: RGBA(r: 0, g: 0, b: 0, a: 0.8), to: &batch)
            BitmapFont.appendText(
                text, x: padding, y: top, scale: scale, color: RGBA(r: 1, g: 1, b: 1, a: 1), to: &batch)
            top += Float(BitmapFont.glyphHeight) * scale + lineSpacing
        }
    }
}
