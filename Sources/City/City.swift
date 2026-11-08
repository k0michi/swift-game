import Dawn
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn
import VectorMath

let canvasSize = Vector2<Float>(1280, 720)
let depthFormat = TextureFormat.depth24Plus
let skyColor = Vector4<Float>(0.70, 0.80, 0.88, 1)

/// An endless city of 1 m voxels, seen from above at an angle, generated as
/// the view moves. Drag or use WASD or the arrow keys to move, the wheel or
/// -/= to zoom, and Q and E to turn. F2 saves a screenshot, and F3 toggles
/// the debug overlay.
///
/// `--focus X Z`, `--zoom METERS` and `--turn QUARTERS` set where the view
/// starts, and `--screenshot` saves a screenshot once the city around it is
/// generated, and quits.
@main
struct City: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.video])
        let window = try createWindow(
            title: "city", w: Int32(canvasSize.x), h: Int32(canvasSize.y),
            flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        let deviceDetails = (try? describe(adapter.getInfo())) ?? []
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)
        var depth = try createDepthTexture(
            device: device, width: configuration.width, height: configuration.height, format: depthFormat)
        let chunkRenderer = try ChunkRenderer(device: device, format: configuration.format, depthFormat: depthFormat)
        let shapeRenderer = try ShapeRenderer(device: device, format: configuration.format, depthFormat: depthFormat)
        let streamer = ChunkStreamer(renderer: chunkRenderer, radius: 12)

        print(
            "Drag or use WASD or the arrow keys to move, the wheel or -/= to zoom, and Q and E to turn. F2 saves a screenshot, and F3 toggles the overlay."
        )

        var camera = IsometricCamera()
        let arguments = CommandLine.arguments
        func values(after flag: String, count: Int) -> [Double]? {
            guard let index = arguments.firstIndex(of: flag), index + count < arguments.count else { return nil }
            let values = arguments[(index + 1)...(index + count)].compactMap { Double($0) }
            return values.count == count ? values : nil
        }
        if let focus = values(after: "--focus", count: 2) {
            (camera.focusX, camera.focusZ) = (focus[0], focus[1])
        }
        if let zoom = values(after: "--zoom", count: 1) {
            camera.zoom = Float(zoom[0])
        }
        if let turns = values(after: "--turn", count: 1) {
            camera.rotate(quarterTurns: Int(turns[0]))
            camera.yaw = camera.targetYaw
        }
        let screenshotsAndQuits = arguments.contains("--screenshot")
        var frameGraph = FrameGraph()
        var fpsCounter = FPSCounter()
        var showsOverlay = true
        var takesScreenshot = false
        var lastFrame = ContinuousClock.now
        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                switch event {
                case let event as KeyboardEvent where event.down && !event.repeat:
                    switch event.key {
                    case .f2: takesScreenshot = true
                    case .f3: showsOverlay.toggle()
                    case .q: camera.rotate(quarterTurns: -1)
                    case .e: camera.rotate(quarterTurns: 1)
                    case .minus: camera.zoom(by: 1.25)
                    case .equals: camera.zoom(by: 0.8)
                    default: break
                    }
                case let event as MouseMotionEvent where !event.state.isEmpty:
                    camera.drag(by: Vector2(event.xrel, event.yrel), canvasHeight: canvasSize.y)
                case let event as MouseWheelEvent:
                    camera.zoom(by: Float.pow(0.88, event.y))
                default:
                    if event.type == .quit || event.type == .windowCloseRequested {
                        isRunning = false
                    } else if event.type == .windowPixelSizeChanged || event.type == .windowMetalViewResized {
                        shouldConfigureSurface = true
                    }
                }
            }
            guard isRunning else { break }
            if shouldConfigureSurface,
                let reconfigured = try? configureSurface(surface, device: device, adapter: adapter, window: window)
            {
                configuration = reconfigured
                depth = try createDepthTexture(
                    device: device, width: configuration.width, height: configuration.height, format: depthFormat)
            }

            let now = ContinuousClock.now
            let frameMilliseconds = milliseconds(now - lastFrame)
            lastFrame = now
            frameGraph.record(frameMilliseconds)
            fpsCounter.record(frameMilliseconds)
            let seconds = min(frameMilliseconds / 1000, 0.1)

            let keys = getKeyboardState()
            var direction = Vector2<Float>.zero
            if keys[.a] || keys[.left] { direction.x -= 1 }
            if keys[.d] || keys[.right] { direction.x += 1 }
            if keys[.w] || keys[.up] { direction.y += 1 }
            if keys[.s] || keys[.down] { direction.y -= 1 }
            camera.move(screen: direction * (camera.zoom * 1.5 * seconds))
            camera.update(duration: seconds)

            let anchor = camera.anchor
            try streamer.update(
                around: ChunkStreamer.chunk(containing: anchor.x, anchor.z), budget: .milliseconds(8))

            let viewProjection = camera.viewProjection(aspectRatio: canvasSize.x / canvasSize.y)
            let visible = streamer.visibleChunks(anchor: anchor, viewProjection: viewProjection)
            let focus = camera.focusOffset
            let drawDistance = Float(streamer.radius * ChunkCoordinate.size)
            let uniforms = ChunkRenderer.Uniforms(
                viewProjection: viewProjection,
                light: Vector4(normalize(Vector3<Float>(-0.45, -1, -0.3)), 0.55),
                fog: Vector4(focus.x, focus.y, drawDistance * 0.7, drawDistance),
                sky: skyColor)

            if screenshotsAndQuits && streamer.pendingCount == 0 && !takesScreenshot {
                takesScreenshot = true
                isRunning = false
            }

            var shapes = ShapeBatch(canvasSize: canvasSize)
            if showsOverlay {
                frameGraph.append(to: &shapes)
                fpsCounter.append(to: &shapes, details: deviceDetails)
                drawStatus(
                    [
                        "FOCUS \(Int(camera.focusX.rounded(.down))), \(Int(camera.focusZ.rounded(.down)))  ZOOM \(Int(camera.zoom)) M",
                        "CHUNKS \(visible.count) DRAWN / \(streamer.chunks.count) LOADED  TRIANGLES \(streamer.triangleCount)",
                        "DRAG/WASD MOVE  WHEEL ZOOM  Q/E TURN  F2 SCREENSHOT  F3 OVERLAY",
                    ], into: &shapes)
            }

            do {
                let texture = try surface.getCurrentTexture()
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try texture.createView(), loadOp: .clear, storeOp: .store,
                                clearValue: Color(
                                    r: Double(skyColor.x), g: Double(skyColor.y), b: Double(skyColor.z), a: 1))
                        ],
                        depthStencilAttachment: RenderPassDepthStencilAttachment(
                            view: depth, depthLoadOp: .clear, depthStoreOp: .discard, depthClearValue: 1)))
                try chunkRenderer.draw(visible, uniforms: uniforms, into: pass)
                try shapeRenderer.draw(shapes, into: pass)
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
                    let saved = Flag()
                    Task {
                        do {
                            print("Saved \(try await saveScreenshot(screenshot))")
                        } catch {
                            print("Could not save a screenshot: \(error)")
                        }
                        saved.isSet = true
                    }
                    // Before quitting, waits for the copy, which Dawn answers
                    // from processEvents.
                    while !isRunning && !saved.isSet {
                        instance.processEvents()
                        await nextFrame()
                    }
                }
            } catch WebGPUError.getCurrentTextureFailed {
                _ = try? configureSurface(surface, device: device, adapter: adapter, window: window)
            }

            instance.processEvents()
            await nextFrame()
        }

        withExtendedLifetime((system, window, instance, adapter, device, surface, chunkRenderer, shapeRenderer)) {}
    }

    /// Lines of status in the bottom-left corner.
    private static func drawStatus(_ lines: [String], into shapes: inout ShapeBatch) {
        let scale: Float = 2
        let lineHeight = Float(BitmapFont.glyphHeight) * scale + 6
        var y = canvasSize.y - lineHeight * Float(lines.count) - 6
        let width = lines.map { BitmapFont.width(of: $0, scale: scale) }.max() ?? 0
        shapes.appendRect(
            from: Vector2(0, y - 6), to: Vector2(width + 16, canvasSize.y), color: Vector4(0, 0, 0, 0.45))
        for line in lines {
            BitmapFont.appendText(line, at: Vector2(8, y), scale: scale, color: Vector4(1, 1, 1, 1), to: &shapes)
            y += lineHeight
        }
    }

    private static func milliseconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) * 1000 + Float(attoseconds) / 1e15
    }
}

@MainActor
private final class Flag {
    var isSet = false
}
