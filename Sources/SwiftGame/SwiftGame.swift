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

private struct DummyImage {
    var width: UInt32
    var height: UInt32
    var pixels: [UInt8]
}

private func makeDummyImage(width: UInt32, height: UInt32) -> DummyImage {
    let pixels = (0..<height).flatMap { y in
        (0..<width).flatMap { x -> [UInt8] in
            let isLight = ((x / 8) + (y / 8)).isMultiple(of: 2)
            return isLight
                ? [0xFF, 0xFF, 0xFF, 0xFF]
                : [0x00, 0x00, 0x00, 0xFF]
        }
    }
    return DummyImage(width: width, height: height, pixels: pixels)
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
        let image = makeDummyImage(width: 64, height: 64)
        let texture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "dummy image",
                usage: [.copyDst, .textureBinding],
                dimension: .`2D`,
                size: Extent3D(
                    width: image.width,
                    height: image.height,
                    depthOrArrayLayers: 1
                ),
                format: .rgba8Unorm
            )
        )
        image.pixels.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: texture),
                data: data,
                dataLayout: TexelCopyBufferLayout(
                    bytesPerRow: image.width * 4,
                    rowsPerImage: image.height
                ),
                writeSize: Extent3D(
                    width: image.width,
                    height: image.height,
                    depthOrArrayLayers: 1
                )
            )
        }
        let textureView = try texture.createView()
        let sampler = try device.createSampler(
            descriptor: SamplerDescriptor(
                label: "dummy image sampler",
                addressModeU: .clampToEdge,
                addressModeV: .clampToEdge,
                addressModeW: .clampToEdge,
                magFilter: .nearest,
                minFilter: .nearest,
                mipmapFilter: .nearest
            )
        )
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "dummy image bind group layout",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0,
                        visibility: .fragment,
                        sampler: SamplerBindingLayout(type: .filtering)
                    ),
                    BindGroupLayoutEntry(
                        binding: 1,
                        visibility: .fragment,
                        texture: TextureBindingLayout(
                            sampleType: .float,
                            viewDimension: .`2D`
                        )
                    ),
                ]
            )
        )
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "dummy image bind group",
                layout: bindGroupLayout,
                entries: [
                    BindGroupEntry(binding: 0, sampler: sampler),
                    BindGroupEntry(binding: 1, textureView: textureView),
                ]
            )
        )
        let pipeline = try createTexturedPipeline(
            device: device,
            format: surfaceFormat,
            bindGroupLayout: bindGroupLayout
        )
        let vertexData: [Float] = [
            -0.5, 0.5, 0.0, 0.0,
            -0.5, -0.5, 0.0, 1.0,
            0.5, 0.5, 1.0, 0.0,
            0.5, -0.5, 1.0, 1.0,
        ]
        let indexData: [UInt16] = [0, 1, 2, 2, 1, 3]
        let vertexBufferSize = UInt64(vertexData.count * MemoryLayout<Float>.stride)
        let vertexBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "triangle vertices",
                usage: [.copyDst, .vertex],
                size: vertexBufferSize
            )
        )
        vertexData.withUnsafeBufferPointer { vertexData in
            queue.writeBuffer(
                vertexBuffer,
                bufferOffset: 0,
                data: UnsafeRawBufferPointer(vertexData)
            )
        }
        let indexBufferSize = UInt64(indexData.count * MemoryLayout<UInt16>.stride)
        let indexBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "quad indices",
                usage: [.copyDst, .index],
                size: indexBufferSize
            )
        )
        indexData.withUnsafeBufferPointer { indexData in
            queue.writeBuffer(
                indexBuffer,
                bufferOffset: 0,
                data: UnsafeRawBufferPointer(indexData)
            )
        }

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
                try drawTexturedQuad(
                    surface: surface,
                    device: device,
                    queue: queue,
                    pipeline: pipeline,
                    bindGroup: bindGroup,
                    vertexBuffer: vertexBuffer,
                    vertexBufferSize: vertexBufferSize,
                    indexBuffer: indexBuffer,
                    indexBufferSize: indexBufferSize,
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
            (
                system, window, instance, adapter, device, surface, queue, texture, textureView,
                sampler, bindGroupLayout, bindGroup, pipeline, vertexBuffer, indexBuffer
            )
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

    private static func createTexturedPipeline(
        device: Device,
        format: TextureFormat,
        bindGroupLayout: BindGroupLayout
    ) throws -> RenderPipeline {
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) uv: vec2f,
                        }

                        @group(0) @binding(0) var imageSampler: sampler;
                        @group(0) @binding(1) var imageTexture: texture_2d<f32>;

                        @vertex
                        fn vertexMain(
                            @location(0) position: vec2f,
                            @location(1) uv: vec2f
                        ) -> VertexOutput {
                            var output: VertexOutput;
                            output.position = vec4f(position, 0.0, 1.0);
                            output.uv = uv;
                            return output;
                        }

                        @fragment
                        fn fragmentMain(@location(0) uv: vec2f) -> @location(0) vec4f {
                            return textureSample(imageTexture, imageSampler, uv);
                        }
                        """
                ),
                label: "triangle"
            )
        )
        let layout = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(bindGroupLayouts: [bindGroupLayout])
        )
        return try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "triangle",
                layout: layout,
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: 4 * UInt64(MemoryLayout<Float>.stride),
                            attributes: [
                                VertexAttribute(
                                    format: .float32x2,
                                    offset: 0,
                                    shaderLocation: 0
                                ),
                                VertexAttribute(
                                    format: .float32x2,
                                    offset: 2 * UInt64(MemoryLayout<Float>.stride),
                                    shaderLocation: 1
                                ),
                            ]
                        )
                    ]
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

    private static func drawTexturedQuad(
        surface: Surface,
        device: Device,
        queue: Queue,
        pipeline: RenderPipeline,
        bindGroup: BindGroup,
        vertexBuffer: Buffer,
        vertexBufferSize: UInt64,
        indexBuffer: Buffer,
        indexBufferSize: UInt64,
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
        renderPass.setBindGroup(groupIndex: 0, group: bindGroup)
        renderPass.setVertexBuffer(
            slot: 0,
            buffer: vertexBuffer,
            offset: 0,
            size: vertexBufferSize
        )
        renderPass.setIndexBuffer(
            buffer: indexBuffer,
            format: .uint16,
            offset: 0,
            size: indexBufferSize
        )
        renderPass.drawIndexed(
            indexCount: 6,
            instanceCount: 1,
            firstIndex: 0,
            baseVertex: 0,
            firstInstance: 0
        )
        renderPass.end()
        let commandBuffer = try commandEncoder.finish()
        queue.submit([commandBuffer])
        try surface.present()
    }
}
