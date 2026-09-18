import Interop
import Testing

@testable import Dawn

@Suite("WebGPU")
struct WebGPUTests {
    @Test
    func surfaceDescriptorPreservesChain() throws {
        final class Owner {}

        let owner = Owner()
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: 1))
        let boundPointer = UnsafeLifetimeBoundRawPointer(
            pointer,
            boundTo: owner
        )
        let tail = SurfaceSourceXlibWindow(
            display: boundPointer,
            window: 42
        )
        let descriptor = SurfaceDescriptor(
            nextInChain: SurfaceSourceMetalLayer(
                nextInChain: tail,
                layer: boundPointer
            ),
            label: "surface"
        )

        let head = try #require(
            descriptor.nextInChain as? SurfaceSourceMetalLayer
        )
        let next = try #require(
            head.chain.next as? SurfaceSourceXlibWindow
        )
        #expect(head.chain.sType == .surfaceSourceMetalLayer)
        #expect(next.chain.sType == .surfaceSourceXlibWindow)
        #expect(next.window == 42)
        #expect(descriptor.label == "surface")
    }

    @Test
    func requestsNullAdapter() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )

        withExtendedLifetime((instance, adapter)) {}
    }

    @Test
    func requestsDeviceFromNullAdapter() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let configuration = SurfaceConfiguration(
            device: device,
            format: .bgra8Unorm,
            width: 1280,
            height: 720
        )

        #expect(configuration.usage == .renderAttachment)
        #expect(configuration.presentMode == .fifo)
        withExtendedLifetime((instance, adapter, device)) {}
    }

    @Test
    func createsBindGroupLayout() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "uniforms",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0,
                        visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(
                            type: .uniform,
                            minBindingSize: 64
                        )
                    )
                ]
            )
        )

        withExtendedLifetime((instance, adapter, device, layout)) {}
    }

    @Test
    func createsBindGroup() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0,
                        visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(
                            type: .uniform,
                            minBindingSize: 64
                        )
                    )
                ]
            )
        )
        let buffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "uniforms",
                usage: .uniform,
                size: 64
            )
        )
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "uniforms",
                layout: layout,
                entries: [
                    BindGroupEntry(
                        binding: 0,
                        buffer: buffer,
                        size: 64
                    )
                ]
            )
        )

        withExtendedLifetime((instance, adapter, device, bindGroup)) {}
    }

    @Test
    func createsShaderModuleFromWGSL() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    nextInChain: ShaderModuleCompilationOptions(
                        strictMath: true
                    ),
                    code: """
                        @compute @workgroup_size(1)
                        fn main() {}
                        """
                ),
                label: "compute"
            )
        )

        withExtendedLifetime((instance, adapter, device, shaderModule)) {}
    }

    @Test
    func shaderModuleSPIRVDescriptorsPreserveCode() throws {
        let spirv: [UInt32] = [0x0723_0203, 0x0001_0000]
        let options = DawnShaderModuleSPIRVOptionsDescriptor(
            allowNonUniformDerivatives: true
        )
        let source = ShaderSourceSPIRV(
            nextInChain: options,
            code: spirv
        )
        let dawnSource = DawnShaderSourceSPIRV(code: spirv)

        #expect(source.chain.sType == .shaderSourceSPIRV)
        #expect(source.code == spirv)
        #expect(
            source.chain.next?.chain.sType
                == .dawnShaderModuleSPIRVOptionsDescriptor
        )
        #expect(dawnSource.chain.sType == .dawnShaderSourceSPIRV)
        #expect(dawnSource.code == spirv)
    }

    @Test
    func createsPipelineLayout() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let firstBindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(entries: [])
        )
        let secondBindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(entries: [])
        )
        let pipelineLayout = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(
                label: "pipeline",
                bindGroupLayouts: [
                    firstBindGroupLayout,
                    secondBindGroupLayout,
                ]
            )
        )

        withExtendedLifetime((instance, adapter, device, pipelineLayout)) {}
    }

    @Test
    func createsVertexAndFragmentStates() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @vertex
                        fn vertexMain(@location(0) position: vec2f) -> @builtin(position) vec4f {
                            return vec4f(position, 0.0, 1.0);
                        }

                        @fragment
                        fn fragmentMain() -> @location(0) vec4f {
                            return vec4f(1.0, 0.0, 0.0, 1.0);
                        }
                        """
                )
            )
        )
        let vertex = VertexState(
            module: shaderModule,
            entryPoint: "vertexMain",
            buffers: [
                VertexBufferLayout(
                    stepMode: .vertex,
                    arrayStride: 8,
                    attributes: [
                        VertexAttribute(
                            format: .float32x2,
                            offset: 0,
                            shaderLocation: 0
                        )
                    ]
                )
            ]
        )
        let fragment = FragmentState(
            module: shaderModule,
            entryPoint: "fragmentMain",
            targets: [
                ColorTargetState(
                    format: .bgra8Unorm,
                    blend: BlendState(
                        color: BlendComponent(
                            operation: .add,
                            srcFactor: .srcAlpha,
                            dstFactor: .oneMinusSrcAlpha
                        ),
                        alpha: BlendComponent(
                            operation: .add,
                            srcFactor: .one,
                            dstFactor: .zero
                        )
                    )
                )
            ]
        )

        #expect(vertex.buffers[0].attributes[0].format == .float32x2)
        #expect(fragment.targets[0].writeMask == .all)
        withExtendedLifetime((instance, adapter, device, vertex, fragment)) {}
    }

    @Test
    func createsRenderPipeline() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) color: vec3f,
                        }

                        @vertex
                        fn vertexMain(
                            @location(0) position: vec2f,
                            @location(1) color: vec3f
                        ) -> VertexOutput {
                            var output: VertexOutput;
                            output.position = vec4f(position, 0.0, 1.0);
                            output.color = color;
                            return output;
                        }

                        @fragment
                        fn fragmentMain(@location(0) color: vec3f) -> @location(0) vec4f {
                            return vec4f(color, 1.0);
                        }
                        """
                )
            )
        )
        let pipelineLayout = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(bindGroupLayouts: [])
        )
        let pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "triangle",
                layout: pipelineLayout,
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: 20,
                            attributes: [
                                VertexAttribute(
                                    format: .float32x2,
                                    offset: 0,
                                    shaderLocation: 0
                                ),
                                VertexAttribute(
                                    format: .float32x3,
                                    offset: 8,
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
                    targets: [ColorTargetState(format: .bgra8Unorm)]
                )
            )
        )

        withExtendedLifetime((instance, adapter, device, pipeline)) {}
    }

    @Test
    func recordsTriangleDraw() async throws {
        let instance = try createInstance()
        let adapter = try await instance.requestAdapter(
            options: RequestAdapterOptions(backendType: .null)
        )
        let device = try await adapter.requestDevice()
        let queue = device.getQueue()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @vertex
                        fn vertexMain(@location(0) position: vec2f) -> @builtin(position) vec4f {
                            return vec4f(position, 0.0, 1.0);
                        }
                        """
                )
            )
        )
        let pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: 8,
                            attributes: [
                                VertexAttribute(
                                    format: .float32x2,
                                    offset: 0,
                                    shaderLocation: 0
                                )
                            ]
                        )
                    ]
                ),
                primitive: PrimitiveState(topology: .triangleList)
            )
        )
        let vertices: [Float] = [0, 0.5, -0.5, -0.5, 0.5, -0.5]
        let bufferSize = UInt64(vertices.count * MemoryLayout<Float>.stride)
        let vertexBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                usage: [.copyDst, .vertex],
                size: bufferSize
            )
        )
        vertices.withUnsafeBufferPointer { vertices in
            queue.writeBuffer(
                vertexBuffer,
                bufferOffset: 0,
                data: UnsafeRawBufferPointer(vertices)
            )
        }
        let commandEncoder = try device.createCommandEncoder()
        let renderPass = try commandEncoder.beginRenderPass(
            descriptor: RenderPassDescriptor(colorAttachments: [])
        )
        renderPass.setPipeline(pipeline)
        renderPass.setVertexBuffer(
            slot: 0,
            buffer: vertexBuffer,
            offset: 0,
            size: bufferSize
        )
        renderPass.draw(
            vertexCount: 3,
            instanceCount: 1,
            firstVertex: 0,
            firstInstance: 0
        )
        renderPass.end()
        let commandBuffer = try commandEncoder.finish()
        queue.submit([commandBuffer])

        withExtendedLifetime(
            (instance, adapter, device, queue, pipeline, vertexBuffer, commandBuffer)
        ) {}
    }
}
