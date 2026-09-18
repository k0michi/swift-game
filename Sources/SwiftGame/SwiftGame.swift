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
        let surfaceFormat = try configure(
            surface: surface,
            device: device,
            adapter: adapter,
            window: window
        )
        let pipeline = try createTrianglePipeline(
            device: device,
            format: surfaceFormat
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
                _ = try? configure(
                    surface: surface,
                    device: device,
                    adapter: adapter,
                    window: window
                )
            }

            do {
                try drawTriangle(
                    surface: surface,
                    device: device,
                    queue: queue,
                    pipeline: pipeline,
                    color: Color(
                        r: Double(0x64) / 0xFF, g: Double(0x95) / 0xFF, b: Double(0xED) / 0xFF,
                        a: 1.0)
                )
            } catch WebGPUError.getCurrentTextureFailed {
                _ = try? configure(
                    surface: surface,
                    device: device,
                    adapter: adapter,
                    window: window
                )
            }

            instance.processEvents()
        }

        withExtendedLifetime(
            (system, window, instance, adapter, device, surface, queue, pipeline)
        ) {}
    }

    private static func configure(
        surface: Surface,
        device: Device,
        adapter: Adapter,
        window: Window
    ) throws -> TextureFormat {
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
        return format
    }

    private static func createTrianglePipeline(
        device: Device,
        format: TextureFormat
    ) throws -> RenderPipeline {
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) color: vec3f,
                        }

                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> VertexOutput {
                            var positions = array(
                                vec2f(0.0, 0.5),
                                vec2f(-0.5, -0.5),
                                vec2f(0.5, -0.5)
                            );
                            var colors = array(
                                vec3f(1.0, 0.0, 0.0),
                                vec3f(0.0, 1.0, 0.0),
                                vec3f(0.0, 0.0, 1.0)
                            );

                            var output: VertexOutput;
                            output.position = vec4f(positions[index], 0.0, 1.0);
                            output.color = colors[index];
                            return output;
                        }

                        @fragment
                        fn fragmentMain(@location(0) color: vec3f) -> @location(0) vec4f {
                            return vec4f(color, 1.0);
                        }
                        """
                ),
                label: "triangle"
            )
        )
        let layout = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(bindGroupLayouts: [])
        )
        return try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "triangle",
                layout: layout,
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain"
                ),
                primitive: PrimitiveState(topology: .triangleList),
                fragment: FragmentState(
                    module: shaderModule,
                    entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format)]
                )
            )
        )
    }

    private static func drawTriangle(
        surface: Surface,
        device: Device,
        queue: Queue,
        pipeline: RenderPipeline,
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
        renderPass.setPipeline(pipeline)
        renderPass.draw(
            vertexCount: 3,
            instanceCount: 1,
            firstVertex: 0,
            firstInstance: 0
        )
        renderPass.end()
        let commandBuffer = try commandEncoder.finish()
        queue.submit([commandBuffer])
        try surface.present()
    }
}
