import Dawn
import Echo
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn
import VectorMath

@main
struct Pong: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.audio, .video])
        let window = try createWindow(
            title: "pong", w: Int32(fieldSize.x), h: Int32(fieldSize.y),
            flags: platformWindowFlags([.highPixelDensity]))
        try hideCursor()

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        let format = try configureSurface(surface, device: device, adapter: adapter, window: window).format
        let renderer = try ShapeRenderer(device: device, format: format)

        let audio = try makeAudioContext(system: system)
        let output = try audio.createSoftClippedOutput()

        var game = PongState()
        var playerTarget = game.playerY
        let tickDuration: Float = 1 / 60
        var accumulator: Float = 0
        var lastFrame = ContinuousClock.now

        while true {
            while let event = pollEvent() {
                switch event {
                case let event as MouseMotionEvent:
                    playerTarget = event.y
                case let event as MouseButtonEvent where event.down:
                    audio.resumeIfSuspended()
                    if game.winner != nil { game = PongState() }
                default:
                    if event.type == .quit || event.type == .windowCloseRequested { return }
                    if event.type == .windowPixelSizeChanged {
                        _ = try? configureSurface(surface, device: device, adapter: adapter, window: window)
                    }
                }
            }

            let now = ContinuousClock.now
            accumulator = min(accumulator + seconds(now - lastFrame), 0.25)
            lastFrame = now
            while accumulator >= tickDuration {
                game.tick(duration: tickDuration, playerTarget: playerTarget)
                accumulator -= tickDuration
            }
            for event in game.events {
                switch event {
                case .hit: try beep(440, on: audio, to: output)
                case .wall: try beep(220, on: audio, to: output)
                case .point: try beep(110, length: 0.3, on: audio, to: output)
                }
            }
            game.events = []

            var batch = ShapeBatch(canvasSize: fieldSize)
            draw(game, blend: accumulator / tickDuration, into: &batch)

            if let texture = try? surface.getCurrentTexture() {
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try texture.createView(), loadOp: .clear, storeOp: .store,
                                clearValue: Color(r: 0.05, g: 0.05, b: 0.08, a: 1))
                        ]))
                try renderer.draw(batch, into: pass)
                pass.end()
                device.getQueue().submit([try encoder.finish()])
                try surface.present()
            }

            instance.processEvents()
            await nextFrame()
        }
    }

    static func draw(_ game: PongState, blend: Float, into batch: inout ShapeBatch) {
        let white = Vector4<Float>(1, 1, 1, 1)
        let gray = Vector4<Float>(1, 1, 1, 0.3)

        for y in stride(from: Float(0), to: fieldSize.y, by: 30) {
            batch.appendRect(from: Vector2(fieldSize.x / 2 - 2, y), to: Vector2(fieldSize.x / 2 + 2, y + 15), color: gray)
        }
        for (score, x) in [(game.playerScore, fieldSize.x / 4), (game.computerScore, fieldSize.x * 3 / 4)] {
            BitmapFont.appendText("\(score)", at: Vector2(x - 20, 24), scale: 8, color: gray, to: &batch)
        }
        for (x, y) in [(paddleX, game.playerY), (fieldSize.x - paddleX, game.computerY)] {
            batch.appendRect(from: Vector2(x, y) - paddleSize / 2, to: Vector2(x, y) + paddleSize / 2, color: white)
        }

        if let winner = game.winner {
            let text = winner == .player ? "YOU WIN" : "YOU LOSE"
            let width = BitmapFont.width(of: text, scale: 4)
            BitmapFont.appendText(
                text, at: Vector2((fieldSize.x - width) / 2, fieldSize.y / 2 - 14), scale: 4, color: white,
                to: &batch)
        } else {
            batch.appendBall(center: mix(game.previousBall, game.ball, blend), radius: ballRadius, color: white)
        }
    }

    static func beep(_ frequency: Float, length: Double = 0.08, on audio: AudioContext, to output: AudioNode) throws {
        guard audio.state == .running else { return }
        let now = audio.currentTime
        let oscillator = audio.createOscillator()
        try oscillator.setType(.square)
        oscillator.frequency.value = frequency
        try oscillator.connect(audio.createEnvelope(at: now, peak: 0.15, decayEnd: length)).connect(output)
        try oscillator.start(now)
        try oscillator.stop(now + length)
    }

    static func seconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) + Float(attoseconds) / 1e18
    }
}
