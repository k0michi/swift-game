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
        let window = try createWindow(title: "text", w: 640, h: 600, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let renderer = try TextRenderer(
            device: device, format: configuration.format, font: try await readAsset("NotoSansJP-Regular.otf"),
            scale: getWindowDisplayScale(window: window))

        let graph = ViewGraph(renderer: renderer, textInput: TextInput(window: window))
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

            // In the middle of the window.
            renderer.begin()
            let screen = single(graph.update(Screen(frame: frame)))
            let size = screen.size(proposedWidth: nil, in: renderer)
            let width = Float(configuration.width) / renderer.scale
            let height = Float(configuration.height) / renderer.scale
            try screen.draw(
                x: (width - size.width) / 2, y: (height - size.height) / 2, proposedWidth: nil, in: renderer)
            try graph.endFrame()

            if let surfaceTexture = try? surface.getCurrentTexture() {
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try surfaceTexture.createView(), loadOp: .clear, storeOp: .store,
                                clearValue: Color(r: 0.05, g: 0.05, b: 0.08, a: 1))
                        ]))
                try renderer.end(into: pass, width: configuration.width, height: configuration.height)
                pass.end()
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
    @State private var sound = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hello, world!").font(size: 28)
            HStack(spacing: 12) {
                TextField("Text", text: $name)
                // Text(name.isEmpty ? "名前を入力してください" : "こんにちは、\(name)さん")
            }
            Text("あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波。")
            // The same buttons, in a style of the game's own.
            HStack(spacing: 16) {
                Button("はじめる") { pressed = "「はじめる」が押されました" }
                Button("つづきから") { pressed = "「つづきから」が押されました" }
            }
            .buttonStyle(GameButtonStyle(color: Color(r: 0.95, g: 0.55, b: 0.15, a: 1)))
            Text(pressed).font(size: 14).foregroundColor(Color(r: 0.7, g: 0.7, b: 0.7, a: 1))
            HStack(spacing: 12) {
                Switch(isOn: $sound)
                Text(sound ? "サウンド: オン" : "サウンド: オフ")
            }
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

// A chunky button, its face over its darker side, which it sinks onto when it
// is pressed, and lighter when the pointer is over it.
struct GameButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        let sink: Float = configuration.isPressed ? 4 : 0
        let face = configuration.isHovered ? color.mixed(with: .white, by: 0.2) : color
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(color.mixed(with: .black, by: 0.45)).offset(y: 4)
            RoundedRectangle(cornerRadius: 12).fill(face).offset(y: sink)
            RoundedRectangle(cornerRadius: 12).stroke(Color(r: 1, g: 1, b: 1, a: 0.5), lineWidth: 2).offset(y: sink)
            configuration.label
                .font(size: 20)
                .foregroundColor(.white)
                .padding(horizontal: 24, vertical: 10)
                .offset(y: sink)
        }
    }
}

// An on-off switch of its own, of shapes and a tap.
struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(horizontalAlignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Color(r: 0.3, g: 0.8, b: 0.45, a: 1) : Color(r: 0.35, g: 0.36, b: 0.42, a: 1))
            Capsule().fill(.white).frame(width: 22, height: 22).padding(3)
        }
        .frame(width: 52, height: 28)
        .onTapGesture { isOn.toggle() }
    }
}

extension Color {
    static let white = Color(r: 1, g: 1, b: 1, a: 1)
    static let black = Color(r: 0, g: 0, b: 0, a: 1)

    /// This color `amount` of the way to `other`.
    func mixed(with other: Color, by amount: Double) -> Color {
        Color(
            r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount,
            a: a + (other.a - a) * amount)
    }
}
