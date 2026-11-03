import Dawn
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn

@main
struct TextSample: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.video])
        defer { withExtendedLifetime(system) {} }
        let window = try createWindow(title: "text", w: 640, h: 560, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let renderer = Compositor(
            device: device, format: configuration.format, scale: try getWindowDisplayScale(window: window))
        renderer.register(try Typesetter(compositor: renderer, font: try await readAsset("NotoSansJP-Regular.otf")))

        let graph = ViewGraph(compositor: renderer, textInput: TextInput(window: window))
        let clock = ContinuousClock()
        let start = clock.now
        var frame = 0
        while true {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested { return }
                if let update = graph.textInput.handle(event) {
                    graph.inputs.append(.text(update))
                } else if let event = event as? KeyboardEvent, event.down {
                    graph.inputs.append(.key(event))
                }
                if let event = event as? MouseMotionEvent {
                    graph.pointer = (event.x, event.y)
                }
                if let event = event as? MouseButtonEvent {
                    graph.pointer = (event.x, event.y)
                    if event.down {
                        graph.clicks.append((event.x, event.y))
                    } else {
                        graph.releases.append((event.x, event.y))
                    }
                }
                if event.type == .windowMouseLeave {
                    graph.pointer = nil
                }
                if event.type == .windowPixelSizeChanged {
                    configuration = (try? configureSurface(surface, device: device, adapter: adapter, window: window)) ?? configuration
                }
                if event.type == .windowDisplayScaleChanged {
                    renderer.scale = try getWindowDisplayScale(window: window)
                }
            }
            frame += 1
            let elapsed = (clock.now - start).components
            graph.time = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            renderer.time = graph.time

            // In the middle of the window.
            renderer.beginFrame()
            let screen = single(graph.update(Screen(frame: frame)))
            let size = screen.size(proposedWidth: nil, in: renderer)
            let width = Float(configuration.width) / renderer.scale
            let height = Float(configuration.height) / renderer.scale
            try screen.draw(
                x: (width - size.width) / 2, y: (height - size.height) / 2, proposedWidth: nil, in: renderer)
            try graph.endFrame()

            if let surfaceTexture = try? surface.getCurrentTexture() {
                let encoder = try device.createCommandEncoder()
                try renderer.render(
                    into: try surfaceTexture.createView(), width: configuration.width, height: configuration.height,
                    clearColor: Color(r: 0.05, g: 0.05, b: 0.08, a: 1), encoder: encoder, present: PresentKind.self)
                device.getQueue().submit([try encoder.finish()])
                try surface.present()
            }

            instance.processEvents()
            await nextFrame()
        }
    }
}

// Two counters that keep their counts, the second of which can go, and its
// count with it.
struct Screen: View {
    var frame: Int
    @State private var showsSecond = true
    @State private var name = ""
    @State private var pressed = "まだ何も押されていません"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hello, world!").font(size: 28)
            HStack(spacing: 12) {
                TextField("Text", text: $name)
                // Text(name.isEmpty ? "名前を入力してください" : "こんにちは、\(name)さん")
            }
            Text("あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波。")
            // Buttons whose faces a shader of their own draws.
            HStack(spacing: 24) {
                GlowButton(title: "はじめる", color: Color(r: 0.95, g: 0.45, b: 0.15, a: 1)) {
                    pressed = "「はじめる」が押されました"
                }
                GlowButton(title: "つづきから", color: Color(r: 0.2, g: 0.5, b: 0.95, a: 1)) {
                    pressed = "「つづきから」が押されました"
                }
            }
            .padding(horizontal: 0, vertical: 6)
            Text(pressed).font(size: 14).foregroundColor(Color(r: 0.7, g: 0.7, b: 0.7, a: 1))
            Counter(title: "A")
            if showsSecond {
                Counter(title: "B")
            }
            Button(showsSecond ? "B を消す" : "B を出す") { showsSecond.toggle() }
            Text("\(frame) フレーム目").font(size: 14).foregroundColor(Color(r: 0.7, g: 0.7, b: 0.7, a: 1))
        }
        .frame(width: 400, alignment: .leading)
    }
}

// A count of its own.
struct Counter: View {
    var title: String
    @State private var count = 0

    var body: some View {
        HStack(spacing: 12) {
            Text("\(title): \(count)").frame(width: 60, alignment: .leading)
            Stepper(value: $count)
        }
    }
}

// Changes a count that another view keeps.
struct Stepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 6) {
            Button("−") { value -= 1 }
            Button("+") { value += 1 }
            Button("リセット") { value = 0 }
        }
    }
}
