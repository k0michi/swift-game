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
/// N switches between the street corner and a town 200 m square, the same
/// each time for its seed.
///
/// `--town` starts in the town, `--seed N` lays it out from another seed,
/// `--tiles N` starts with N by N copies of the street, `--benchmark` times
/// fixed views and quits, and `--extra-lamps N` adds lamps that light nothing,
/// to time many of them.
///
/// `--hour H`, `--focus X Y Z`, `--zoom METERS`, `--yaw DEGREES` and
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
        let device = try await adapter.requestDevice { reason in
            print("The GPU device was lost: \(reason)")
        }
        let deviceDetails = (try? describe(adapter.getInfo())) ?? []
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let clock = ContinuousClock()
        func argument(after flag: String) -> Int? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else {
                return nil
            }
            return Int(CommandLine.arguments[index + 1])
        }
        let townScene = SceneChoice.town(seed: UInt64(max(argument(after: "--seed") ?? defaultTownSeed, 0)))
        var choice: SceneChoice =
            CommandLine.arguments.contains("--town") ? townScene : .tiles(max(argument(after: "--tiles") ?? 1, 1))
        let extraLamps = argument(after: "--extra-lamps") ?? 0
        var (scene, renderer) = try await loadScene(
            choice, extraLamps: extraLamps, device: device, instance: instance, format: configuration.format)
        let shapeRenderer = try ShapeRenderer(device: device, format: configuration.format)

        let arguments = CommandLine.arguments
        func values(after flag: String, count: Int) -> [Float]? {
            guard let index = arguments.firstIndex(of: flag), index + count < arguments.count else { return nil }
            let values = arguments[(index + 1)...(index + count)].compactMap { Float($0) }
            return values.count == count ? values : nil
        }
        var time = TimeOfDay(hour: values(after: "--hour", count: 1)?[0] ?? 17.5)
        // The middle copy of the street corner, when there are several.
        let middle = scene.middleTileOffset
        var camera = Camera(focus: Vector3(20 + middle, 1.5, 24 + middle))
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
        let startFocus: Vector3<Float>
        if arguments.contains("--first-person") {
            let at = values(after: "--at", count: 2) ?? [scene.spawn.x, scene.spawn.y]
            startFocus = Vector3(at[0], Scene.streetLevel, at[1])
        } else {
            startFocus = camera.focus
        }
        // Timing and screenshots want the same world every time.
        try await renderer.load(around: startFocus, everything: screenshotsAndQuits || arguments.contains("--benchmark"))
        if arguments.contains("--benchmark") {
            try await runBenchmark(
                device: device, instance: instance, renderer: renderer, scene: scene, format: configuration.format)
            withExtendedLifetime((system, window, instance, adapter, device, surface, renderer, shapeRenderer)) {}
            return
        }
        // On the plaza, facing south, toward the road and the shops.
        let spawn = values(after: "--at", count: 2) ?? [scene.spawn.x, scene.spawn.y]
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
        // Counts down the frames until the other scene loads, so that the
        // notice of it is on the screen meanwhile.
        var framesUntilSwitch: Int?
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
                    case .n where framesUntilSwitch == nil: framesUntilSwitch = 2
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
            if framesUntilSwitch == 0 {
                framesUntilSwitch = nil
                if case .town = choice { choice = .tiles(1) } else { choice = townScene }
                (scene, renderer) = try await loadScene(
                    choice, extraLamps: extraLamps, device: device, instance: instance, format: configuration.format)
                // Start again in the middle of what is there now.
                let middle = scene.middleTileOffset
                camera.focus = Vector3(20 + middle, 1.5, 24 + middle)
                let (yaw, pitch) = (walker.yaw, walker.pitch)
                walker = FirstPerson(feet: Vector3(scene.spawn.x, Scene.streetLevel, scene.spawn.y), yaw: yaw)
                walker.pitch = pitch
                try await renderer.load(around: isFirstPerson ? walker.eye : camera.focus, everything: false)
                lastFrame = clock.now
            }
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
                walker.update(input: direction, running: keys[.lShift], duration: seconds, grid: scene.voxels)
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
                        "TIME \(clockText)\(timeRuns ? " RUNNING" : "")  LAMPS \(litLamps) LIT  BLOOM \(bloomOn ? "ON" : "OFF")  \(framesUntilSwitch == nil ? "SCENE \(Int(scene.width)) M  N SWITCH" : "LOADING...")",
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
                    frame: frame, focus: isFirstPerson ? walker.eye : camera.focus, materials: materials, lights: lights, character: showsCharacter ? character.mesh() : VoxelMesh(),
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

            if let frames = framesUntilSwitch {
                framesUntilSwitch = frames - 1
            }
            instance.processEvents()
            await nextFrame()
        }

        withExtendedLifetime((system, window, instance, adapter, device, surface, renderer, shapeRenderer)) {}
    }

    /// What to show.
    private enum SceneChoice {
        /// Copies of the street corner, this many on each side.
        case tiles(Int)
        case town(seed: UInt64)
    }

    private static let defaultTownSeed = 20_261_108

    /// Builds a scene and what draws it.
    private static func loadScene(
        _ choice: SceneChoice, extraLamps: Int, device: Device, instance: Instance, format: TextureFormat
    ) async throws -> (Scene, Renderer) {
        var scene: Scene
        switch choice {
        case .tiles(let tiles): scene = await Scene(tiles: tiles)
        case .town(let seed): scene = Scene(townSeed: seed)
        }
        // Lamps too far away to light anything, for timing many lamps.
        for _ in 0..<extraLamps {
            scene.lights.append(
                PointLight(position: Vector3(-1000, 2, -1000), color: Vector3(1, 1, 1), radius: 5, schedule: .always))
        }
        // Errors in making the pipelines show up once, here, rather than as
        // a warning about an invalid object each frame.
        device.pushErrorScope(.validation)
        let renderer = try Renderer(device: device, surfaceFormat: format, scene: scene)
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
        return (scene, renderer)
    }

    /// What the scene's shaders read for a view: from `camera`, or through
    /// the eyes of `walker` if there is one.
    static func frameUniforms(
        scene: Scene, time: TimeOfDay, lampCount: Int, camera: Camera, walker: FirstPerson?, aspect: Float
    ) -> FrameUniforms {
        let cells = LightGrid.dimensions(sceneWidth: scene.width, sceneDepth: scene.depth)
        let sun = sunView(of: scene, toward: time.lightDirection, fittedTo: walker == nil ? camera : nil, aspect: aspect)
        let (zenith, horizon) = time.skyColors
        let ground = Vector3<Float>(0.35, 0.3, 0.25) * (horizon.x + horizon.y + horizon.z) / 3
        return FrameUniforms(
            viewProjection: walker?.viewProjection(aspectRatio: aspect) ?? camera.viewProjection(aspectRatio: aspect),
            sunViewProjection: sun.viewProjection,
            sunDirection: Vector4(time.lightDirection, 0),
            sunColor: Vector4(time.lightColor, 0),
            skyColor: Vector4(zenith, 0),
            horizonColor: Vector4(horizon, 0),
            groundColor: Vector4(ground, 0),
            viewDirection: Vector4(walker?.forward ?? camera.forward, 0),
            params: Vector4(Float(lampCount), time.exposure, 1.6, sun.bias),
            gridSize: Vector4(
                Float(scene.voxels.width), Float(scene.voxels.height), Float(scene.voxels.depth), Float(voxelsPerMeter)),
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

    /// The sun's view for its shadow map, and how far to offset depths in it
    /// to keep surfaces from shadowing themselves. With `fittedTo`, it covers
    /// only what that camera shows, for finer shadows and fewer chunks to
    /// draw, as parallel sunlight can reach what is shown only from within
    /// the same rectangle of the sun's view. Otherwise it covers the scene.
    private static func sunView(
        of scene: Scene, toward direction: Vector3<Float>, fittedTo camera: Camera?, aspect: Float
    ) -> (viewProjection: Matrix4x4<Float>, bias: Float) {
        let center = Vector3<Float>(scene.width / 2, 4, scene.depth / 2)
        let up: Vector3<Float> = abs(direction.y) > 0.99 ? Vector3(0, 0, 1) : Vector3(0, 1, 0)
        let size = max(scene.width, scene.depth)
        let distance = size * 2
        let view = Matrix4x4<Float>.lookAt(
            eye: center + direction * distance, target: center, up: up, handedness: .right)
        let far = distance * 2

        func bounds(of points: [Vector3<Float>]) -> (low: Vector2<Float>, high: Vector2<Float>) {
            var low = Vector2<Float>(repeating: .greatestFiniteMagnitude)
            var high = -low
            for point in points {
                let seen = (view * Vector4(point, 1)).xy
                low = min(low, seen)
                high = max(high, seen)
            }
            return (low, high)
        }
        var sceneCorners: [Vector3<Float>] = []
        for x in [0, scene.width] {
            for y in [0, Scene.size.height] {
                for z in [0, scene.depth] {
                    sceneCorners.append(Vector3(x, y, z))
                }
            }
        }
        var (low, high) = bounds(of: sceneCorners)
        if let camera {
            let shown = bounds(of: camera.visiblePoints(aspectRatio: aspect, heights: 0...Scene.size.height))
            low = max(low, shown.low)
            high = min(high, shown.high)
            // Whole meters of width, and whole texels of position, so that
            // the shadows do not crawl as the view moves.
            let middle = (low + high) / 2
            let halfSize = Vector2<Float>(
                ((high.x - low.x) / 2 + 1).rounded(.up), ((high.y - low.y) / 2 + 1).rounded(.up))
            let texel = halfSize * (2 / Float(Renderer.shadowMapSize))
            let snapped = Vector2(
                (middle.x / texel.x).rounded() * texel.x, (middle.y / texel.y).rounded() * texel.y)
            low = snapped - halfSize
            high = snapped + halfSize
        }
        let projection = Matrix4x4<Float>.orthographic(
            left: low.x, right: high.x, bottom: low.y, top: high.y, near: 1, far: far, handedness: .right,
            depth: .zeroToOne)
        return (projection * view, 0.096 / far)
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
    var error: (any Error)?
}
