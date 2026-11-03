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
        let window = try createWindow(title: "text", w: 640, h: 480, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let renderer = try TextRenderer(
            device: device, format: configuration.format, font: try await readAsset("NotoSansJP-Regular.otf"),
            scale: getWindowDisplayScale(window: window))

        let graph = ViewGraph(renderer: renderer)
        var frame = 0
        while true {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested { return }
                if let event = event as? MouseButtonEvent, event.down {
                    graph.clicks.append((event.x, event.y))
                }
                if event.type == .windowPixelSizeChanged {
                    configuration = (try? configureSurface(surface, device: device, adapter: adapter, window: window)) ?? configuration
                }
                if event.type == .windowDisplayScaleChanged {
                    renderer.scale = try getWindowDisplayScale(window: window)
                }
            }
            frame += 1

            // In the middle of the window.
            renderer.begin()
            let screen = single(graph.update(Screen(frame: frame)))
            let size = screen.size(proposedWidth: nil, in: renderer)
            let width = Float(configuration.width) / renderer.scale
            let height = Float(configuration.height) / renderer.scale
            try screen.draw(
                x: (width - size.width) / 2, y: (height - size.height) / 2, proposedWidth: nil, in: renderer)
            graph.clicks.removeAll()

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hello, world!").font(size: 28)
            Text("あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波。")
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
