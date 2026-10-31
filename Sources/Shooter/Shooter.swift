import Dawn
import Echo
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import RealModule
import SDL3
import SDL3Dawn
import VectorMath

let canvasSize = Vector2<Float>(800, 480)
let ticksPerSecond: Float = 60
let depthFormat = TextureFormat.depth24Plus

/// A 3D shooting game of plain shapes: the ship flies to the mouse and fires
/// while the button is held; a click or enter starts again after a crash.
/// F2 saves a screenshot, and F3 toggles the frame graph and the FPS.
@main
struct Shooter: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.audio, .video])
        let window = try createWindow(
            title: "shooter", w: Int32(canvasSize.x), h: Int32(canvasSize.y),
            flags: platformWindowFlags([.highPixelDensity]))
        // A crosshair stands in for it.
        try hideCursor()

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)
        var depth = try createDepthTexture(
            device: device, width: configuration.width, height: configuration.height, format: depthFormat)
        let meshRenderer = try MeshRenderer(device: device, format: configuration.format, depthFormat: depthFormat)
        let shapeRenderer = try ShapeRenderer(device: device, format: configuration.format, depthFormat: depthFormat)

        var sounds: Sounds?
        do {
            sounds = try Sounds(system: system)
        } catch {
            print("Sound is unavailable: \(error)")
        }

        print(
            "Steer with the mouse and hold the button to fire. Press F2 to save a screenshot, and F3 to toggle the frame graph and FPS."
        )
        if audioWaitsForUserGesture {
            print("Click or press a key to turn on sound.")
        }

        var state = ShooterState()
        var frameGraph = FrameGraph()
        var fpsCounter = FPSCounter()
        var showsOverlay = true
        var shownTitle = ""
        var restarts = false
        var firesOnce = false
        var takesScreenshot = false
        var tickAccumulator: Float = 0
        var lastFrame = ContinuousClock.now
        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                if (event as? MouseButtonEvent)?.down == true || (event as? KeyboardEvent)?.down == true {
                    sounds?.context.resumeIfSuspended()
                }
                switch event {
                case let event as MouseButtonEvent where event.down:
                    restarts = true
                    // A click shorter than a tick still fires.
                    firesOnce = true
                case let event as KeyboardEvent where event.down && !event.repeat:
                    switch event.key {
                    case .f2: takesScreenshot = true
                    case .f3: showsOverlay.toggle()
                    case .return: restarts = true
                    default: break
                    }
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
            // Run as many fixed ticks as the elapsed time covers. The cap keeps a
            // backgrounded tab from running a long burst of ticks when it returns.
            tickAccumulator = min(tickAccumulator + frameMilliseconds / 1000, 0.25)
            while tickAccumulator >= 1 / ticksPerSecond {
                if state.isOver && restarts {
                    state.restart()
                }
                restarts = false
                // The ship flies to where the mouse points in its plane, so
                // that it stays under the crosshair.
                let mouse = getMouseState()
                let target = ChaseCamera(following: state.ship).pointInShipPlane(under: Vector2(mouse.x, mouse.y))
                let (score, bullets, wasOver) = (state.score, state.bullets.count, state.isOver)
                state.tick(
                    duration: 1 / ticksPerSecond, target: target, fires: mouse.flags.contains(.left) || firesOnce)
                firesOnce = false
                sounds?.play(
                    shot: state.bullets.count > bullets, hit: state.score > score, crash: state.isOver && !wasOver)
                tickAccumulator -= 1 / ticksPerSecond
            }

            let title = "score \(state.score) - best \(state.best)"
            if title != shownTitle {
                shownTitle = title
                try? setWindowTitle(window: window, title: title)
            }

            var meshes = MeshBatch()
            draw(state, into: &meshes)
            var shapes = ShapeBatch(canvasSize: canvasSize)
            drawHUD(of: state, into: &shapes)
            drawCrosshair(at: Vector2(getMouseState().x, getMouseState().y), into: &shapes)
            if showsOverlay {
                frameGraph.append(to: &shapes)
                fpsCounter.append(to: &shapes)
            }

            let camera = ChaseCamera(following: state.ship)
            do {
                let texture = try surface.getCurrentTexture()
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try texture.createView(), loadOp: .clear,
                                storeOp: .store, clearValue: Color(r: 0.02, g: 0.02, b: 0.08, a: 1))
                        ],
                        depthStencilAttachment: RenderPassDepthStencilAttachment(
                            view: depth, depthLoadOp: .clear, depthStoreOp: .discard, depthClearValue: 1)))
                try meshRenderer.draw(
                    meshes, viewProjection: camera.viewProjection, lightDirection: Vector3(-0.3, -1, -0.5), ambient: 0.35,
                    into: pass)
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

        withExtendedLifetime((system, window, instance, adapter, device, surface, meshRenderer, shapeRenderer, sounds)) {}
    }

    private static func draw(_ state: ShooterState, into meshes: inout MeshBatch) {
        func place(at position: Vector3<Float>, scale: Vector3<Float>) -> Matrix4x4<Float> {
            .translation(position) * .scale(scale)
        }

        for star in state.stars {
            meshes.append(.cube, transform: place(at: star, scale: Vector3(repeating: 0.06)), color: Vector4(1, 1, 1, 1))
        }
        meshes.append(
            .cube, transform: place(at: Vector3(0, -4.6, (farZ + nearZ) / 2), scale: Vector3(14, 0.05, (nearZ - farZ) / 2)),
            color: Vector4(0.08, 0.1, 0.25, 1))
        for z in state.stripes {
            meshes.append(
                .cube, transform: place(at: Vector3(0, -4.5, z), scale: Vector3(14, 0.05, 0.15)),
                color: Vector4(0.2, 0.5, 0.9, 1))
        }

        if !state.isOver {
            // The pyramid's apex points ahead, down -z, and the ship banks as
            // it turns.
            let position = Matrix4x4<Float>.translation(Vector3(state.ship, 0))
            let roll = Matrix4x4<Float>.rotation(angle: -state.bank * 0.6, axis: Vector3(0, 0, 1))
            let pointAhead = Matrix4x4<Float>.rotation(angle: -.pi / 2, axis: Vector3(1, 0, 0))
            let shape = Matrix4x4<Float>.scale(Vector3(0.7, 1.1, 0.25))
            meshes.append(.pyramid, transform: position * roll * pointAhead * shape, color: Vector4(0.85, 0.9, 1, 1))
        }
        for bullet in state.bullets {
            meshes.append(.cube, transform: place(at: bullet, scale: Vector3(0.07, 0.07, 0.6)), color: Vector4(1, 0.9, 0.3, 1))
        }
        for enemy in state.enemies {
            meshes.append(
                .octahedron,
                transform: .translation(enemy.position) * enemy.rotation * .scale(Vector3(repeating: enemyRadius)),
                color: enemy.kind == .homing ? Vector4(0.3, 1, 0.45, 1) : Vector4(1, 0.3, 0.4, 1))
        }
        for piece in state.debris {
            meshes.append(
                .cube, transform: place(at: piece.position, scale: Vector3(repeating: 0.12 * piece.life)),
                color: Vector4(1, 0.6, 0.2, 1))
        }
    }

    private static func drawHUD(of state: ShooterState, into shapes: inout ShapeBatch) {
        let text = "SCORE \(state.score)"
        let scale: Float = 3
        BitmapFont.appendText(
            text, at: Vector2(canvasSize.x - BitmapFont.width(of: text, scale: scale) - 12, 12), scale: scale,
            color: Vector4(1, 1, 1, 1), to: &shapes)
        if state.isOver {
            let message = "GAME OVER - PRESS ENTER"
            let width = BitmapFont.width(of: message, scale: scale)
            BitmapFont.appendText(
                message, at: (canvasSize - Vector2(width, Float(BitmapFont.glyphHeight) * scale)) / 2,
                scale: scale, color: Vector4(1, 0.4, 0.4, 1), to: &shapes)
        }
    }

    /// Four ticks around the mouse, with a gap in the middle.
    private static func drawCrosshair(at point: Vector2<Float>, into shapes: inout ShapeBatch) {
        let color = Vector4<Float>(1, 1, 1, 0.85)
        for (direction, across) in [(Vector2<Float>(1, 0), Vector2<Float>(0, 1)), (Vector2(0, 1), Vector2(1, 0))] {
            for side: Float in [-1, 1] {
                let near = point + direction * side * 4
                let far = point + direction * side * 11
                let width = across * 1
                shapes.appendRect(from: min(near, far) - width, to: max(near, far) + width, color: color)
            }
        }
    }

    private static func milliseconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) * 1000 + Float(attoseconds) / 1e15
    }
}

/// The game's sounds, made of Web Audio nodes for each.
@MainActor
final class Sounds {
    let context: AudioContext
    private let master: AudioNode
    private let noise: AudioBuffer

    init(system: System) throws {
        context = try makeAudioContext(system: system)
        master = try context.createSoftClippedOutput()
        noise = try context.createNoiseBuffer()
        context.resumeIfSuspended()
    }

    func play(shot: Bool, hit: Bool, crash: Bool) {
        // While the context is not running, as in a browser before a user
        // gesture, its time stands still, so sounds would pile up.
        guard context.state == .running, shot || hit || crash else { return }
        let now = context.currentTime
        do {
            if shot {
                let tone = context.createOscillator()
                try tone.setType(.square)
                try tone.frequency.setValueAtTime(1400, startTime: now)
                    .exponentialRampToValueAtTime(600, endTime: now + 0.06)
                try tone.connect(context.createEnvelope(at: now, peak: 0.04, decayEnd: 0.06)).connect(master)
                try tone.start(now)
                try tone.stop(now + 0.06)
            }
            if hit {
                try playNoise(at: now, duration: 0.3, peak: 0.5, cutoff: 2500, to: 200)
            }
            if crash {
                try playNoise(at: now, duration: 0.8, peak: 0.9, cutoff: 1500, to: 60)
            }
        } catch {
            print("Could not play a sound: \(error)")
        }
    }

    // Noise through a low-pass filter whose cutoff falls exponentially.
    private func playNoise(at start: Double, duration: Double, peak: Float, cutoff from: Float, to: Float) throws {
        let source = context.createBufferSource()
        try source.setBuffer(noise)
        let filter = context.createBiquadFilter()
        filter.type = .lowpass
        try filter.frequency.setValueAtTime(from, startTime: start)
            .exponentialRampToValueAtTime(to, endTime: start + duration)
        try source.connect(filter).connect(context.createEnvelope(at: start, peak: peak, decayEnd: duration))
            .connect(master)
        try source.start(start)
        try source.stop(start + duration)
    }
}

/// The camera, which follows the ship a little, from behind and above.
struct ChaseCamera {
    static let fovY: Float = .pi / 3
    let eye: Vector3<Float>
    let target: Vector3<Float>

    init(following ship: Vector2<Float>) {
        let follow = Vector3(ship * 0.4, 0)
        eye = follow + Vector3(0, 2.5, 9)
        target = follow + Vector3(0, 0, -20)
    }

    var viewProjection: Matrix4x4<Float> {
        let projection = Matrix4x4<Float>.perspective(
            fovY: Self.fovY, aspectRatio: canvasSize.x / canvasSize.y, near: 0.1, far: 200, handedness: .right,
            depth: .zeroToOne)
        let view = Matrix4x4<Float>.lookAt(eye: eye, target: target, up: Vector3(0, 1, 0), handedness: .right)
        return projection * view
    }

    /// Where the ray from the eye through `point` on the canvas meets the
    /// ship's plane, z = 0.
    func pointInShipPlane(under point: Vector2<Float>) -> Vector2<Float> {
        let forward = normalize(target - eye)
        let right = normalize(cross(forward, Vector3(0, 1, 0)))
        let up = cross(right, forward)
        let ndc = Vector2(point.x / canvasSize.x * 2 - 1, 1 - point.y / canvasSize.y * 2)
        let halfHeight = Float.tan(Self.fovY / 2)
        let direction =
            forward + right * (ndc.x * halfHeight * canvasSize.x / canvasSize.y) + up * (ndc.y * halfHeight)
        // The plane is ahead of the eye, which is behind it at positive z.
        let distance = -eye.z / direction.z
        return (eye + direction * distance).xy
    }
}
