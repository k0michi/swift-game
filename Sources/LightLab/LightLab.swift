import Dawn
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import RealModule
import SDL3
import SDL3Dawn
import VectorMath

let canvasSize = Vector2<Float>(1280, 720)

/// A street of 1/8 m voxels for trying out light through a day: the sun's
/// shadows, the light of the sky in the shade, colored lamps that walls
/// stop, glass, and bloom.
///
/// Drag with the left button or use WASD or the arrow keys to move, drag with
/// the right button to turn and tilt, R and F tilt too, the wheel or -/=
/// zooms, and Q and E turn to the next diagonal. [ and ] turn the clock
/// back and on, T lets it run, and B toggles bloom. F2 saves a screenshot,
/// and F3 toggles the overlay.
///
/// V walks the street instead: WASD to walk, shift to run, space to jump, and the mouse to
/// look, after a click holds it; Esc lets it go.
///
/// `--hour H`, `--focus X Y Z`, `--zoom METERS`, `--yaw DEGREES` and
/// `--benchmark` times fixed views and quits, and `--extra-lamps N` adds lamps
/// that light nothing, to time many of them.
///
/// `--pitch DEGREES` set where it starts, `--first-person` starts walking,
/// `--at X Z` and `--look YAW PITCH` set where and which way, and `--screenshot` saves a
/// screenshot after 150 frames, and quits.
@main
struct LightLab: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.video])
        let window = try createWindow(
            title: "light lab", w: Int32(canvasSize.x), h: Int32(canvasSize.y),
            flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        let deviceDetails = (try? describe(adapter.getInfo())) ?? []
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let clock = ContinuousClock()
        var start = clock.now
        var scene = Scene()
        // Lamps too far away to light anything, for timing many lamps.
        if let index = CommandLine.arguments.firstIndex(of: "--extra-lamps"), index + 1 < CommandLine.arguments.count,
            let count = Int(CommandLine.arguments[index + 1])
        {
            for _ in 0..<count {
                scene.lights.append(
                    PointLight(position: Vector3(-1000, 2, -1000), color: Vector3(1, 1, 1), radius: 5, schedule: .always))
            }
        }
        let built = clock.now - start
        start = clock.now
        // Errors in making the pipelines show up once, here, rather than as
        // a warning about an invalid object each frame.
        device.pushErrorScope(.validation)
        let renderer = try Renderer(device: device, surfaceFormat: configuration.format, scene: scene)
        let popped = Flag()
        Task {
            if let error = try? await device.popErrorScope() {
                print("Could not set up the renderer: \(error.message)")
            }
            popped.isSet = true
        }
        while !popped.isSet {
            instance.processEvents()
            await nextFrame()
        }
        print(
            "Built the scene in \(built), meshed and uploaded it in \(clock.now - start): \(renderer.triangleCount) triangles, \(scene.lights.count) lamps."
        )
        let shapeRenderer = try ShapeRenderer(device: device, format: configuration.format)

        let arguments = CommandLine.arguments
        func values(after flag: String, count: Int) -> [Float]? {
            guard let index = arguments.firstIndex(of: flag), index + count < arguments.count else { return nil }
            let values = arguments[(index + 1)...(index + count)].compactMap { Float($0) }
            return values.count == count ? values : nil
        }
        var time = TimeOfDay(hour: values(after: "--hour", count: 1)?[0] ?? 17.5)
        var camera = Camera(focus: Vector3(20, 1.5, 24))
        if let focus = values(after: "--focus", count: 3) {
            camera.focus = Vector3(focus[0], focus[1], focus[2])
        }
        if let zoom = values(after: "--zoom", count: 1) {
            camera.zoom = zoom[0]
        }
        if let yaw = values(after: "--yaw", count: 1) {
            camera.yaw = yaw[0] * .pi / 180
            camera.targetYaw = camera.yaw
        }
        if let pitch = values(after: "--pitch", count: 1) {
            camera.pitch = pitch[0] * .pi / 180
        }
        let screenshotsAndQuits = arguments.contains("--screenshot")
        if arguments.contains("--benchmark") {
            try await runBenchmark(
                device: device, instance: instance, renderer: renderer, scene: scene, format: configuration.format)
            withExtendedLifetime((system, window, instance, adapter, device, surface, renderer, shapeRenderer)) {}
            return
        }
        // On the plaza, facing south, toward the road and the shops.
        let spawn = values(after: "--at", count: 2) ?? [16, 20]
        var walker = FirstPerson(feet: Vector3(spawn[0], Scene.streetLevel, spawn[1]), yaw: .pi)
        if let look = values(after: "--look", count: 2) {
            walker.yaw = look[0] * .pi / 180
            walker.pitch = look[1] * .pi / 180
        }
        var isFirstPerson = arguments.contains("--first-person")
        var holdsMouse = false
        // A browser may take a while to grant the mouse, or refuse for good.
        var framesHoldingMouse = 0
        var mouseWasEverHeld = false
        var mouseIsRefused = false
        func holdMouse(_ holds: Bool) {
            guard holds != holdsMouse, !(holds && mouseIsRefused) else { return }
            do {
                try setWindowRelativeMouseMode(window: window, enabled: holds)
                holdsMouse = holds
                framesHoldingMouse = 0
            } catch {
                print("Could not hold the mouse: \(error)")
            }
        }

        print(
            "Left-drag or WASD to move, right-drag or R/F to turn and tilt, the wheel to zoom, Q/E to turn to a diagonal, [ and ] to change the hour, T to let time run, B to toggle bloom, F2 to save a screenshot, F3 for the overlay. V walks: WASD, shift to run, space to jump, click to look with the mouse, Esc to let it go."
        )

        // The walking person is left out for now.
        let showsCharacter = false
        var character = Character(at: Vector3(12, Scene.streetLevel, 18), walking: 10...36)
        var frameGraph = FrameGraph()
        var fpsCounter = FPSCounter()
        var showsOverlay = true
        var timeRuns = false
        var bloomOn = true
        var takesScreenshot = false
        var frameCount = 0
        var elapsed: Float = 0
        var lastFrame = clock.now
        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                switch event {
                case let event as KeyboardEvent where event.down && !event.repeat:
                    switch event.key {
                    case .f2: takesScreenshot = true
                    case .f3: showsOverlay.toggle()
                    case .v:
                        isFirstPerson.toggle()
                        if !isFirstPerson { holdMouse(false) }
                    case .escape: holdMouse(false)
                    case .q where !isFirstPerson: camera.rotate(quarterTurns: -1)
                    case .e where !isFirstPerson: camera.rotate(quarterTurns: 1)
                    case .minus: camera.zoom *= 1.25
                    case .equals: camera.zoom *= 0.8
                    case .t: timeRuns.toggle()
                    case .b: bloomOn.toggle()
                    default: break
                    }
                case let event as MouseButtonEvent where isFirstPerson && event.down:
                    holdMouse(true)
                case let event as MouseMotionEvent where isFirstPerson:
                    // Without the mouse held, as when it cannot be, by dragging.
                    if holdsMouse || !event.state.isEmpty {
                        walker.look(by: Vector2(event.xrel, event.yrel))
                    }
                case let event as MouseMotionEvent where event.state.contains(.left):
                    camera.drag(by: Vector2(event.xrel, event.yrel), canvasHeight: canvasSize.y)
                case let event as MouseMotionEvent where !event.state.isDisjoint(with: [.right, .middle]):
                    camera.orbit(yaw: event.xrel * 0.006, pitch: event.yrel * 0.006)
                case let event as MouseWheelEvent where !isFirstPerson:
                    camera.zoom *= Float.pow(0.88, event.y)
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
            }

            let now = clock.now
            let frameMilliseconds = milliseconds(now - lastFrame)
            lastFrame = now
            frameGraph.record(frameMilliseconds)
            fpsCounter.record(frameMilliseconds)
            let seconds = min(frameMilliseconds / 1000, 0.1)
            elapsed += seconds

            if holdsMouse {
                framesHoldingMouse += 1
                if windowHoldsMouse() {
                    mouseWasEverHeld = true
                } else if framesHoldingMouse > 30 {
                    // Looks by dragging instead.
                    mouseIsRefused = !mouseWasEverHeld
                    holdMouse(false)
                }
            }

            let keys = getKeyboardState()
            var direction = Vector2<Float>.zero
            if keys[.a] || keys[.left] { direction.x -= 1 }
            if keys[.d] || keys[.right] { direction.x += 1 }
            if keys[.w] || keys[.up] { direction.y += 1 }
            if keys[.s] || keys[.down] { direction.y -= 1 }
            if isFirstPerson {
                if keys[.space] { walker.jump() }
                walker.update(input: direction, running: keys[.lShift], duration: seconds, grid: scene.grid)
            } else {
                camera.move(screen: direction * (camera.zoom * 1.5 * seconds))
                var tilt: Float = 0
                if keys[.r] { tilt += 1 }
                if keys[.f] { tilt -= 1 }
                camera.orbit(yaw: 0, pitch: tilt * 1.2 * seconds)
                camera.update(duration: seconds)
            }
            var hours: Float = timeRuns ? 0.1 : 0
            if keys[.leftBracket] { hours -= 2 }
            if keys[.rightBracket] { hours += 2 }
            time.hour = (time.hour + hours * seconds).truncatingRemainder(dividingBy: 24)
            if time.hour < 0 { time.hour += 24 }
            if showsCharacter { character.update(duration: seconds) }

            let schedule = ScheduleState(night: time.night, elapsed: elapsed)
            let (materials, lights, litLamps) = lighting(scene: scene, schedule: schedule)
            let frame = frameUniforms(
                scene: scene, time: time, lampCount: litLamps, camera: camera,
                walker: isFirstPerson ? walker : nil, aspect: canvasSize.x / canvasSize.y)

            var shapes = ShapeBatch(canvasSize: canvasSize)
            if showsOverlay {
                frameGraph.append(to: &shapes)
                fpsCounter.append(to: &shapes, details: deviceDetails)
                let minutes = Int((time.hour - time.hour.rounded(.down)) * 60)
                let clockText = "\(Int(time.hour)):\(minutes < 10 ? "0" : "")\(minutes)"
                drawStatus(
                    [
                        "TIME \(clockText)\(timeRuns ? " RUNNING" : "")  LAMPS \(litLamps) LIT  BLOOM \(bloomOn ? "ON" : "OFF")",
                        "TRIANGLES \(renderer.triangleCount)  VOXEL 1/8 M",
                        isFirstPerson
                            ? "WALKING AT \(meters(walker.feet.x)), \(meters(walker.feet.y)), \(meters(walker.feet.z))  WASD WALK  SHIFT RUN  SPACE JUMP  CLICK+MOUSE LOOK  ESC RELEASE  V CAMERA"
                            : "L-DRAG/WASD MOVE  R-DRAG/R/F TURN+TILT  WHEEL ZOOM  [ ] HOUR  T RUN  B BLOOM  V WALK",
                    ], into: &shapes)
            }

            frameCount += 1
            if screenshotsAndQuits && frameCount == 150 {
                takesScreenshot = true
                isRunning = false
            }

            do {
                let texture = try surface.getCurrentTexture()
                let encoder = try device.createCommandEncoder()
                try renderer.draw(
                    frame: frame, materials: materials, lights: lights, character: showsCharacter ? character.mesh() : VoxelMesh(),
                    bloomStrength: bloomOn ? 0.06 : 0, into: try texture.createView(), width: configuration.width,
                    height: configuration.height, encoder: encoder
                ) { pass in
                    try shapeRenderer.draw(shapes, into: pass)
                }
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

        withExtendedLifetime((system, window, instance, adapter, device, surface, renderer, shapeRenderer)) {}
    }

    /// What the scene's shaders read for a view: from `camera`, or through
    /// the eyes of `walker` if there is one.
    static func frameUniforms(
        scene: Scene, time: TimeOfDay, lampCount: Int, camera: Camera, walker: FirstPerson?, aspect: Float
    ) -> FrameUniforms {
        let cells = LightGrid.dimensions(sceneWidth: Scene.size.width, sceneDepth: Scene.size.depth)
        let (zenith, horizon) = time.skyColors
        let ground = Vector3<Float>(0.35, 0.3, 0.25) * (horizon.x + horizon.y + horizon.z) / 3
        return FrameUniforms(
            viewProjection: walker?.viewProjection(aspectRatio: aspect) ?? camera.viewProjection(aspectRatio: aspect),
            sunViewProjection: sunViewProjection(toward: time.lightDirection),
            sunDirection: Vector4(time.lightDirection, 0),
            sunColor: Vector4(time.lightColor, 0),
            skyColor: Vector4(zenith, 0),
            horizonColor: Vector4(horizon, 0),
            groundColor: Vector4(ground, 0),
            viewDirection: Vector4(walker?.forward ?? camera.forward, 0),
            params: Vector4(Float(lampCount), time.exposure, 1.6, 0),
            gridSize: Vector4(
                Float(scene.grid.width), Float(scene.grid.height), Float(scene.grid.depth), Float(voxelsPerMeter)),
            eye: Vector4(walker?.eye ?? .zero, walker == nil ? 0 : 1),
            lightGrid: Vector4(
                LightGrid.cellSize, Float(cells.width), Float(cells.depth), 0))
    }

    /// Which lamps and glowing materials are on, and how bright.
    struct ScheduleState {
        var night: Float = 0
        var elapsed: Float

        func at(night: Float) -> Self {
            var copy = self
            copy.night = night
            return copy
        }

        func brightness(_ schedule: Material.Schedule) -> Float {
            switch schedule {
            case .always: 1
            case .night: night
            case .blinkA: elapsed.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.03
            case .blinkB: elapsed.truncatingRemainder(dividingBy: 1) < 0.5 ? 0.03 : 1
            case .signalRed, .signalYellow, .signalGreen:
                // Green 6 s, yellow 2 s, red 6 s.
                {
                    let phase = elapsed.truncatingRemainder(dividingBy: 14)
                    let lit: Material.Schedule = phase < 6 ? .signalGreen : phase < 8 ? .signalYellow : .signalRed
                    return lit == schedule ? 1 : 0.03
                }()
            }
        }
    }

    /// The materials and lamps as the shaders read them: two vectors each.
    static func lighting(scene: Scene, schedule: ScheduleState) -> (
        materials: [Vector4<Float>], lights: [Vector4<Float>], litCount: Int
    ) {
        var materials: [Vector4<Float>] = []
        for material in Materials.table {
            let emission = material.emission * schedule.brightness(material.schedule)
            materials.append(Vector4(material.linearColor, emission))
            materials.append(Vector4(Float(material.kind.rawValue), material.roughness, 0, 0))
        }
        // Every lamp, in the order of the grid; those that are off, in black.
        var lights: [Vector4<Float>] = []
        var litCount = 0
        for light in scene.lights {
            var brightness = schedule.brightness(light.schedule)
            if brightness > 0.05 {
                litCount += 1
            } else {
                brightness = 0
            }
            lights.append(Vector4(light.position, light.radius))
            lights.append(Vector4(light.color * brightness, 0))
        }
        return (materials, lights, litCount)
    }

    /// The sun's view of the whole scene, for its shadow map.
    private static func sunViewProjection(toward direction: Vector3<Float>) -> Matrix4x4<Float> {
        let center = Vector3<Float>(Scene.size.width / 2, 4, Scene.size.depth / 2)
        let up: Vector3<Float> = abs(direction.y) > 0.99 ? Vector3(0, 0, 1) : Vector3(0, 1, 0)
        let view = Matrix4x4<Float>.lookAt(
            eye: center + direction * 80, target: center, up: up, handedness: .right)
        let extent: Float = 32
        let projection = Matrix4x4<Float>.orthographic(
            left: -extent, right: extent, bottom: -extent, top: extent, near: 1, far: 160, handedness: .right,
            depth: .zeroToOne)
        return projection * view
    }

    /// Lines of status in the bottom-left corner.
    private static func drawStatus(_ lines: [String], into shapes: inout ShapeBatch) {
        let scale: Float = 2
        let lineHeight = Float(BitmapFont.glyphHeight) * scale + 6
        var y = canvasSize.y - lineHeight * Float(lines.count) - 6
        let width = lines.map { BitmapFont.width(of: $0, scale: scale) }.max() ?? 0
        shapes.appendRect(from: Vector2(0, y - 6), to: Vector2(width + 16, canvasSize.y), color: Vector4(0, 0, 0, 0.45))
        for line in lines {
            BitmapFont.appendText(line, at: Vector2(8, y), scale: scale, color: Vector4(1, 1, 1, 1), to: &shapes)
            y += lineHeight
        }
    }

    /// A length to a tenth of a meter.
    private static func meters(_ value: Float) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    private static func milliseconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) * 1000 + Float(attoseconds) / 1e15
    }
}

@MainActor
final class Flag {
    var isSet = false
}
