import Dawn
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn
import VectorMath

/// A bullet-dodging game: the white ball follows the mouse, and yellow balls
/// come in from the edges, faster and more often over time, bouncing off each
/// other. A click starts a new round after a hit, F2 saves a screenshot, and
/// F3 toggles the frame graph and the FPS.
@main
struct SwiftGame: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.audio, .video])
        // The window is the field, in points.
        let window = try createWindow(
            title: "swift-game", w: Int32(fieldWidth), h: Int32(fieldHeight),
            flags: platformWindowFlags([.highPixelDensity]))
        try hideCursor()

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        let deviceDetails = (try? describe(adapter.getInfo())) ?? []
        let format = try configureSurface(surface, device: device, adapter: adapter, window: window).format
        let renderer = try ShapeRenderer(device: device, format: format)

        var sound: SoundEffects?
        do {
            sound = try SoundEffects(system: system)
        } catch {
            print("Sound is unavailable: \(error)")
        }

        print(
            "Move the mouse to dodge the yellow bullets. Press F2 to save a screenshot, and F3 to toggle the frame graph and FPS."
        )
        if audioWaitsForUserGesture {
            print("Click or press a key to turn on sound.")
        }

        var game = GameState()
        var frameGraph = FrameGraph()
        var fpsCounter = FPSCounter()
        var showsOverlay = true
        var takesScreenshot = false
        var shownTitle = ""
        var tickAccumulator: Float = 0
        var lastFrame = ContinuousClock.now
        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                if (event as? MouseButtonEvent)?.down == true || (event as? KeyboardEvent)?.down == true {
                    sound?.resume()
                }
                switch event {
                case let event as MouseMotionEvent:
                    game.player = clamp(Vector2(event.x, event.y), .zero, fieldSize)
                case let event as MouseButtonEvent where event.down && game.isOver:
                    game.restart()
                    sound?.restart()
                case let event as KeyboardEvent where event.down && event.key == .f2 && !event.repeat:
                    takesScreenshot = true
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
                _ = try? configureSurface(surface, device: device, adapter: adapter, window: window)
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
            var batch = ShapeBatch(canvasSize: fieldSize)
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
                fpsCounter.append(to: &batch, details: deviceDetails)
            }

            let background: Color =
                game.isOver
                ? Color(r: 0.45, g: 0.1, b: 0.1, a: 1)
                : Color(r: 100.0 / 255, g: 149.0 / 255, b: 237.0 / 255, a: 1)
            do {
                let texture = try surface.getCurrentTexture()
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try texture.createView(), loadOp: .clear,
                                storeOp: .store, clearValue: background)
                        ]))
                try renderer.draw(batch, into: pass)
                pass.end()
                var screenshot: TextureCopy?
                if takesScreenshot {
                    takesScreenshot = false
                    do {
                        screenshot = try copyTexture(texture, device: device, encoder: encoder)
                    } catch {
                        print("Could not take a screenshot: \(error)")
                    }
                }
                device.getQueue().submit([try encoder.finish()])
                try surface.present()
                if let screenshot {
                    Task {
                        do {
                            print("Saved \(try await saveScreenshot(screenshot))")
                        } catch {
                            print("Could not save a screenshot: \(error)")
                        }
                    }
                }
            } catch WebGPUError.getCurrentTextureFailed {
                _ = try? configureSurface(surface, device: device, adapter: adapter, window: window)
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
}
