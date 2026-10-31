import Dawn
import ProcessMemory
import VectorMath

/// Recent frame intervals for the profiler-style graph, oldest first from `next`.
public struct FrameGraph {
    static let capacity = 240
    static let barWidth: Float = 2
    static let pixelsPerMillisecond: Float = 3
    static let maxMilliseconds: Float = 50

    var samples = [Float](repeating: 0, count: capacity)
    var next = 0

    public init() {}

    public mutating func record(_ milliseconds: Float) {
        samples[next] = milliseconds
        next = (next + 1) % Self.capacity
    }

    // Draws the frame intervals as bars in the bottom-right corner, like the
    // Minecraft profiler: green up to 60 FPS, yellow up to 30 FPS, red beyond.
    // Thin lines mark 16.7 ms (60 FPS) and 33.3 ms (30 FPS).
    public func append(to batch: inout ShapeBatch) {
        let width = Float(Self.capacity) * Self.barWidth
        let left = batch.canvasSize.x - width
        let bottom = batch.canvasSize.y
        let height = Self.maxMilliseconds * Self.pixelsPerMillisecond

        batch.appendRect(
            from: Vector2(left, bottom - height), to: Vector2(left + width, bottom), color: Vector4(0, 0, 0, 0.45))

        for offset in 0..<Self.capacity {
            let milliseconds = samples[(next + offset) % Self.capacity]
            guard milliseconds > 0 else { continue }
            let barLeft = left + Float(offset) * Self.barWidth
            let barHeight = min(milliseconds, Self.maxMilliseconds) * Self.pixelsPerMillisecond
            let color =
                if milliseconds <= 1000.0 / 60 + 1 {
                    Vector4<Float>(0.3, 0.9, 0.3, 1)
                } else if milliseconds <= 1000.0 / 30 + 1 {
                    Vector4<Float>(0.95, 0.85, 0.2, 1)
                } else {
                    Vector4<Float>(0.95, 0.25, 0.2, 1)
                }
            batch.appendRect(
                from: Vector2(barLeft, bottom - barHeight), to: Vector2(barLeft + Self.barWidth, bottom),
                color: color)
        }

        for milliseconds: Float in [1000.0 / 60, 1000.0 / 30] {
            let y = bottom - milliseconds * Self.pixelsPerMillisecond
            batch.appendRect(
                from: Vector2(left, y - 0.5), to: Vector2(left + width, y + 0.5), color: Vector4(1, 1, 1, 0.6))
        }
    }
}

/// Frames per second, averaged over half a second so the number is readable,
/// and the memory the process uses, read as often.
public struct FPSCounter {
    static let interval: Float = 500

    var frames = 0
    var milliseconds: Float = 0
    var text = "--.- FPS"
    var memoryText = memoryDescription()

    public init() {}

    public mutating func record(_ frameMilliseconds: Float) {
        frames += 1
        milliseconds += frameMilliseconds
        guard milliseconds >= Self.interval else { return }
        let fps = Float(frames) * 1000 / milliseconds
        text = "\(formatTenths(fps)) FPS  \(formatTenths(milliseconds / Float(frames))) ms"
        memoryText = Self.memoryDescription()
        frames = 0
        milliseconds = 0
    }

    // "memory 123.4 MB", with the peak when it was more, or nothing if the
    // platform cannot tell.
    static func memoryDescription() -> String? {
        guard let current = currentMemory() else { return nil }
        func megabytes(_ bytes: UInt64) -> String {
            "\(formatTenths(Float(bytes) / Float(1 << 20))) MB"
        }
        let peak = peakMemory().flatMap { $0 > current ? ", peak \(megabytes($0))" : nil } ?? ""
        return "memory \(megabytes(current))\(peak)"
    }

    // Draws the FPS in the top-left corner with the dot font, and the memory
    // used, what was built, with what for what, and `details`, such as
    // `describe(_:)` of the adapter, in smaller dots under it, over a dark
    // backdrop and with a shadow so they stay readable on any background.
    public func append(to batch: inout ShapeBatch, details: [String] = []) {
        let build = [
            "\(BuildInfo.version) \(BuildInfo.configuration)",
            "Swift \(BuildInfo.swiftVersion) \(BuildInfo.triple)",
        ]
        let lines: [(text: String, scale: Float)] =
            [(text, 2)] + ([memoryText].compactMap(\.self) + build + details).map { ($0, 1) }
        let padding: Float = 4
        let lineSpacing: Float = 3

        let width = lines.map { BitmapFont.width(of: $0.text, scale: $0.scale) }.max() ?? 0
        let height = lines.map { Float(BitmapFont.glyphHeight) * $0.scale }.reduce(0, +)
            + lineSpacing * Float(lines.count - 1)
        batch.appendRect(
            from: .zero, to: Vector2(width, height) + padding * 2, color: Vector4(0, 0, 0, 0.45))
        var origin = Vector2<Float>(repeating: padding)
        for (text, scale) in lines {
            BitmapFont.appendText(
                text, at: origin + scale / 2, scale: scale, color: Vector4(0, 0, 0, 0.8), to: &batch)
            BitmapFont.appendText(text, at: origin, scale: scale, color: Vector4(1, 1, 1, 1), to: &batch)
            origin.y += Float(BitmapFont.glyphHeight) * scale + lineSpacing
        }
    }
}

/// Lines for the debug overlay on what WebGPU says of the adapter: its name,
/// its backend and kind, and its vendor, architecture and driver, leaving out
/// what it does not say. A browser says little, to keep pages from telling
/// devices apart.
public func describe(_ info: AdapterInfo) -> [String] {
    let name = [info.device, info.description].first { !$0.isEmpty }
    let backend =
        switch info.backendType {
        case .undefined: "unknown backend"
        case .null: "null"
        case .webGPU: "WebGPU"
        case .d3D11: "D3D11"
        case .d3D12: "D3D12"
        case .metal: "Metal"
        case .vulkan: "Vulkan"
        case .openGL: "OpenGL"
        case .openGLES: "OpenGL ES"
        }
    let kind: String? =
        switch info.adapterType {
        case .discreteGPU: "discrete GPU"
        case .integratedGPU: "integrated GPU"
        case .cpu: "CPU"
        case .unknown: nil
        }
    let source = [info.vendor, info.architecture].filter { !$0.isEmpty }.joined(separator: " ")
    let driver = info.description == name ? "" : info.description
    return [name, [backend, kind].compactMap(\.self).joined(separator: ", "), source, driver]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
}
