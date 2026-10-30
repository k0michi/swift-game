import Dawn
import VectorMath

/// Draws mesh batches into a render pass, lit by one directional light, with
/// depth: the pass needs a depth attachment of the format the renderer is
/// made for.
@MainActor
public final class MeshRenderer {
    private let queue: Queue
    private let pipeline: RenderPipeline
    private let vertexBuffer: GrowingBuffer
    private let uniformBuffer: Buffer
    private let bindGroup: BindGroup

    // The uniforms: the transform from world space to clip space, then the
    // direction the light shines in and how much light reaches faces turned
    // away from it.
    private struct Uniforms {
        var viewProjection: Matrix4x4<Float>
        var light: Vector4<Float>
    }

    public init(device: Device, format: TextureFormat, depthFormat: TextureFormat) throws {
        queue = device.getQueue()
        vertexBuffer = GrowingBuffer(device: device, label: "mesh vertices", usage: .vertex)
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            viewProjection: mat4x4f,
                            light: vec4f,
                        }

                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;

                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) normal: vec3f,
                            @location(1) color: vec4f,
                        }

                        @vertex
                        fn vertexMain(
                            @location(0) position: vec3f,
                            @location(1) normal: vec3f,
                            @location(2) color: vec4f
                        ) -> VertexOutput {
                            var output: VertexOutput;
                            output.position = uniforms.viewProjection * vec4f(position, 1.0);
                            output.normal = normal;
                            output.color = color;
                            return output;
                        }

                        @fragment
                        fn fragmentMain(
                            @location(0) normal: vec3f,
                            @location(1) color: vec4f
                        ) -> @location(0) vec4f {
                            let ambient = uniforms.light.w;
                            let diffuse = max(dot(normalize(normal), -uniforms.light.xyz), 0.0);
                            return vec4f(color.rgb * (ambient + (1.0 - ambient) * diffuse), color.a);
                        }
                        """
                ),
                label: "meshes"
            )
        )
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "mesh uniforms",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, minBindingSize: UInt64(MemoryLayout<Uniforms>.size)))
                ]))
        uniformBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "mesh uniforms", usage: [.uniform, .copyDst], size: UInt64(MemoryLayout<Uniforms>.size)))
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "mesh uniforms", layout: bindGroupLayout,
                entries: [BindGroupEntry(binding: 0, buffer: uniformBuffer, offset: 0, size: UInt64(MemoryLayout<Uniforms>.size))]))
        let floatSize = UInt64(MemoryLayout<Float>.stride)
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "meshes",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "meshes", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: UInt64(MeshBatch.floatsPerVertex) * floatSize,
                            attributes: [
                                VertexAttribute(format: .float32x3, offset: 0, shaderLocation: 0),
                                VertexAttribute(format: .float32x3, offset: 3 * floatSize, shaderLocation: 1),
                                VertexAttribute(format: .float32x4, offset: 6 * floatSize, shaderLocation: 2),
                            ]
                        )
                    ]
                ),
                primitive: PrimitiveState(topology: .triangleList, frontFace: .ccw, cullMode: .back),
                depthStencil: DepthStencilState(format: depthFormat, depthWriteEnabled: true, depthCompare: .less),
                fragment: FragmentState(
                    module: shaderModule,
                    entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format, blend: .alphaBlending)]
                )
            )
        )
    }

    /// Records `batch` into `pass`, seen through `viewProjection`, the
    /// transform from world space to clip space, and lit from
    /// `lightDirection`, the direction the light shines in. `ambient` is how
    /// much light reaches faces turned away from it, from 0 to 1.
    public func draw(
        _ batch: MeshBatch, viewProjection: Matrix4x4<Float>, lightDirection: Vector3<Float>, ambient: Float,
        into pass: RenderPassEncoder
    ) throws {
        guard batch.vertexCount > 0 else { return }
        let uniforms = Uniforms(viewProjection: viewProjection, light: Vector4(normalize(lightDirection), ambient))
        withUnsafeBytes(of: uniforms) { data in
            queue.writeBuffer(uniformBuffer, bufferOffset: 0, data: data)
        }
        let buffer = try vertexBuffer.write(batch.vertices, queue: queue)
        pass.setPipeline(pipeline)
        pass.setBindGroup(groupIndex: 0, group: bindGroup)
        pass.setVertexBuffer(slot: 0, buffer: buffer, offset: 0, size: UInt64(batch.vertices.count * 4))
        pass.draw(vertexCount: UInt32(batch.vertexCount), instanceCount: 1, firstVertex: 0, firstInstance: 0)
    }
}
