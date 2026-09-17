import Dawn
import SDL3
import SDL3Dawn

private enum DemoError: Error {
    case surfaceFormatUnavailable
    case surfaceAlphaModeUnavailable
    case surfacePresentModeUnavailable
    case renderAttachmentUnsupported
    case invalidWindowPixelSize
}

@main
@MainActor
struct SwiftGame {
    static func main() async throws {
        let system = try `init`(flags: [.video])

        var windowFlags: WindowFlags = [.resizable, .highPixelDensity]
        #if os(macOS)
            windowFlags.insert(.metal)
        #endif

        let window = try createWindow(
            title: "Window",
            w: 1280,
            h: 720,
            flags: windowFlags
        )

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)

        #if os(macOS)
            let backendType = BackendType.metal
        #elseif os(Windows)
            let backendType = BackendType.d3D12
        #else
            let backendType = BackendType.vulkan
        #endif

        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: backendType)
        )
        let device = try await adapter.requestDevice()
        let queue = device.getQueue()
        try configure(
            surface: surface,
            device: device,
            adapter: adapter,
            window: window
        )

        var isRunning = true

        while isRunning {
            var shouldConfigureSurface = false
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested {
                    isRunning = false
                }
                if event.type == .windowPixelSizeChanged
                    || event.type == .windowMetalViewResized
                {
                    shouldConfigureSurface = true
                }
            }

            guard isRunning else { break }

            if shouldConfigureSurface {
                try? configure(
                    surface: surface,
                    device: device,
                    adapter: adapter,
                    window: window
                )
            }

            do {
                try clear(
                    surface: surface,
                    device: device,
                    queue: queue,
                    color: Color(
                        r: Double(0x64) / 0xFF, g: Double(0x95) / 0xFF, b: Double(0xED) / 0xFF,
                        a: 1.0)
                )
            } catch WebGPUError.getCurrentTextureFailed {
                try? configure(
                    surface: surface,
                    device: device,
                    adapter: adapter,
                    window: window
                )
            }

            instance.processEvents()
        }

        withExtendedLifetime((system, window, instance, adapter, device, surface, queue)) {}
    }

    private static func configure(
        surface: Surface,
        device: Device,
        adapter: Adapter,
        window: Window
    ) throws {
        let capabilities = try surface.getCapabilities(adapter: adapter)
        guard capabilities.usages.contains(.renderAttachment) else {
            throw DemoError.renderAttachmentUnsupported
        }
        guard let format = capabilities.formats.first else {
            throw DemoError.surfaceFormatUnavailable
        }
        guard
            let alphaMode = capabilities.alphaModes.contains(.auto)
                ? CompositeAlphaMode.auto
                : capabilities.alphaModes.first
        else {
            throw DemoError.surfaceAlphaModeUnavailable
        }
        guard
            let presentMode = capabilities.presentModes.contains(.fifo)
                ? PresentMode.fifo
                : capabilities.presentModes.first
        else {
            throw DemoError.surfacePresentModeUnavailable
        }
        let size = try getWindowSizeInPixels(window: window)
        guard size.w > 0, size.h > 0 else {
            throw DemoError.invalidWindowPixelSize
        }

        try surface.configure(
            SurfaceConfiguration(
                device: device,
                format: format,
                usage: .renderAttachment,
                width: UInt32(size.w),
                height: UInt32(size.h),
                viewFormats: [],
                alphaMode: alphaMode,
                presentMode: presentMode
            )
        )
    }

    private static func clear(
        surface: Surface,
        device: Device,
        queue: Queue,
        color: Color
    ) throws {
        let texture = try surface.getCurrentTexture()
        let view = try texture.createView()
        let commandEncoder = try device.createCommandEncoder()
        let renderPass = try commandEncoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                colorAttachments: [
                    RenderPassColorAttachment(
                        view: view,
                        loadOp: .clear,
                        storeOp: .store,
                        clearValue: color
                    )
                ]
            )
        )
        renderPass.end()
        let commandBuffer = try commandEncoder.finish()
        queue.submit([commandBuffer])
        try surface.present()
    }
}
