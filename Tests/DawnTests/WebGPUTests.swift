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
}
