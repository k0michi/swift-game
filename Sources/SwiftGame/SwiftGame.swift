import Dawn
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn
import VectorMath

private enum SetupError: Error {
    case surfaceFormatUnavailable
    case surfaceAlphaModeUnavailable
    case surfacePresentModeUnavailable
    case renderAttachmentUnsupported
    case invalidWindowPixelSize
}

/// A bullet-dodging game: the white ball follows the mouse, and yellow balls
/// come in from the edges, faster and more often over time, bouncing off each
/// other. A click starts a new round after a hit, and F3 toggles the frame
/// graph and the FPS.
@main
@MainActor
struct SwiftGame {
    #if os(Emscripten)
    typealias DefaultExecutorFactory = BrowserExecutorFactory
    #endif

    #if os(Emscripten)
    static func main() async throws {
        try await run()
    }
    #else
    static func main() {
        runMain(run)
    }
    #endif

    private static func run() async throws {
        let system = try `init`(flags: [.audio, .video])

        var windowFlags: WindowFlags = [.highPixelDensity]
        #if os(macOS)
            windowFlags.insert(.metal)
        #endif
        // The window is the field, in points.
        let window = try createWindow(
            title: "swift-game", w: Int32(fieldWidth), h: Int32(fieldHeight), flags: windowFlags)
        try hideCursor()

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)

        #if os(macOS)
            let backendType = BackendType.metal
        #elseif os(Windows)
            let backendType = BackendType.d3D12
        #elseif os(Emscripten)
            let backendType = BackendType.undefined
        #else
            let backendType = BackendType.vulkan
        #endif

        // The game only needs compatibility mode, which the WebGL 2 fallback offers too.
        #if os(Emscripten)
            let featureLevel = FeatureLevel.compatibility
        #else
            let featureLevel = FeatureLevel.core
        #endif

        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(featureLevel: featureLevel, backendType: backendType)
        )
        let device = try await adapter.requestDevice()
        let format = try configure(surface: surface, device: device, adapter: adapter, window: window)
        let renderer = try Renderer(device: device, format: format)

        var sound: SoundEffects?
        do {
            sound = try SoundEffects()
        } catch {
            print("Sound is unavailable: \(error)")
        }

        print("Move the mouse to dodge the yellow bullets. Press F3 to toggle the frame graph and FPS.")
        #if os(Emscripten)
            print("Click or press a key to turn on sound.")
        #endif

        var game = Game()
        var frameGraph = FrameGraph()
        var fpsCounter = FPSCounter()
        var showsOverlay = true
        var shownTitle = ""
        var tickAccumulator: Float = 0
        var lastFrame = ContinuousClock.now
        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                switch event {
                case let event as MouseMotionEvent:
                    game.player = clamp(Vector2(event.x, event.y), .zero, fieldSize)
                case let event as MouseButtonEvent where event.down && game.isOver:
                    game.restart()
                    sound?.restart()
                case let event as KeyboardEvent where event.down && event.key == .f3 && !event.repeat:
                    showsOverlay.toggle()
                default:
                    if event.type == .quit || event.type == .windowCloseRequested {
                        isRunning = false
                    } else if event.type == .windowPixelSizeChanged
                        || event.type == .windowMetalViewResized
                    {
                        shouldConfigureSurface = true
                    }
                }
            }
            guard isRunning else { break }
            if shouldConfigureSurface {
                _ = try? configure(surface: surface, device: device, adapter: adapter, window: window)
            }

            let now = ContinuousClock.now
            let frameMilliseconds = milliseconds(now - lastFrame)
            lastFrame = now
            frameGraph.record(frameMilliseconds)
            fpsCounter.record(frameMilliseconds)
            // Run as many fixed ticks as the elapsed time covers. The cap keeps a
            // backgrounded tab from running a long burst of ticks when it returns.
            tickAccumulator = min(tickAccumulator + frameMilliseconds / 1000, 0.25)
            let wasOver = game.isOver
            while tickAccumulator >= tickDuration {
                game.tick()
                tickAccumulator -= tickDuration
            }
            if let bounce = game.strongestBounce {
                sound?.bounce(speed: bounce.speed, x: bounce.x, fieldWidth: fieldWidth)
                game.strongestBounce = nil
            }
            if game.isOver && !wasOver {
                sound?.gameOver()
            }

            let title = "\(formatTenths(game.elapsed)) s - best \(formatTenths(game.best)) s"
            if title != shownTitle {
                shownTitle = title
                try? setWindowTitle(window: window, title: title)
            }

            // How far the frame is between the last tick and the next one.
            let blend = game.isOver ? 1 : tickAccumulator / tickDuration
            var batch = Batch()
            for bullet in game.bullets {
                batch.appendBall(
                    center: mix(bullet.previousPosition, bullet.position, blend), radius: bulletRadius,
                    color: Vector4(1, 0.85, 0.2, 1))
            }
            batch.appendBall(
                center: game.player, radius: playerRadius,
                color: game.isOver ? Vector4(1, 0.3, 0.3, 1) : Vector4(1, 1, 1, 1))
            if showsOverlay {
                frameGraph.append(to: &batch)
                fpsCounter.append(to: &batch)
            }

            let background =
                game.isOver
                ? Vector4<Float>(0.45, 0.1, 0.1, 1)
                : Vector4<Float>(100.0 / 255, 149.0 / 255, 237.0 / 255, 1)
            do {
                try renderer.draw(batch, background: background, to: surface)
            } catch WebGPUError.getCurrentTextureFailed {
                _ = try? configure(surface: surface, device: device, adapter: adapter, window: window)
            }

            instance.processEvents()
            await nextFrame()
        }

        withExtendedLifetime((system, window, instance, adapter, device, surface, renderer, sound)) {}
    }

    private static func milliseconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) * 1000 + Float(attoseconds) / 1e15
    }

    private static func configure(
        surface: Surface,
        device: Device,
        adapter: Adapter,
        window: Window
    ) throws -> TextureFormat {
        let capabilities = try surface.getCapabilities(adapter: adapter)
        guard capabilities.usages.contains(.renderAttachment) else {
            throw SetupError.renderAttachmentUnsupported
        }
        guard let format = capabilities.formats.first else {
            throw SetupError.surfaceFormatUnavailable
        }
        guard
            let alphaMode = capabilities.alphaModes.contains(.auto)
                ? CompositeAlphaMode.auto
                : capabilities.alphaModes.first
        else {
            throw SetupError.surfaceAlphaModeUnavailable
        }
        guard
            let presentMode = capabilities.presentModes.contains(.fifo)
                ? PresentMode.fifo
                : capabilities.presentModes.first
        else {
            throw SetupError.surfacePresentModeUnavailable
        }
        let size = try getWindowSizeInPixels(window: window)
        guard size.w > 0, size.h > 0 else {
            throw SetupError.invalidWindowPixelSize
        }

        try surface.configure(
            SurfaceConfiguration(
                device: device,
                format: format,
                usage: .renderAttachment,
                width: UInt32(size.w),
                height: UInt32(size.h),
                viewFormats: [],
                alphaMode: alphaMode,
                presentMode: presentMode
            )
        )
        return format
    }
}
