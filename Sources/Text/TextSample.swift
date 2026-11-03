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
        let window = try createWindow(title: "text", w: 640, h: 360, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let renderer = try TextRenderer(
            device: device, format: configuration.format, font: try await readAsset("NotoSansJP-Regular.otf"),
            scale: getWindowDisplayScale(window: window))

        var frame = 0
        while true {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested { return }
                if event.type == .windowPixelSizeChanged {
                    configuration = (try? configureSurface(surface, device: device, adapter: adapter, window: window)) ?? configuration
                }
                if event.type == .windowDisplayScaleChanged {
                    renderer.scale = try getWindowDisplayScale(window: window)
                }
            }
            frame += 1

            let screen = VStack(spacing: 12) {
                Text("Hello, world!").font(size: 32)
                Text("こんにちは、世界。").font(size: 32)
                HStack(spacing: 6) {
                    Text("FreeType").foregroundColor(Color(r: 0.4, g: 0.8, b: 1, a: 1))
                    Text("+")
                    Text("HarfBuzz").foregroundColor(Color(r: 1, g: 0.6, b: 0.3, a: 1))
                }
                Text("\(frame) フレーム目").font(size: 14).foregroundColor(Color(r: 0.7, g: 0.7, b: 0.7, a: 1))
            }

            // In the middle of the window.
            renderer.begin()
            let size = screen.size(in: renderer)
            let width = Float(configuration.width) / renderer.scale
            let height = Float(configuration.height) / renderer.scale
            try screen.draw(x: (width - size.width) / 2, y: (height - size.height) / 2, in: renderer)

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
