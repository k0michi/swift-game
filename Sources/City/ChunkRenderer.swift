import Dawn
import VectorMath

/// A chunk's mesh on the GPU.
@MainActor
final class GPUChunk {
    let vertexBuffer: Buffer
    let indexBuffer: Buffer
    let indexCount: UInt32
    /// How many voxels tall the chunk is, for culling.
    let height: Int

    init(vertexBuffer: Buffer, indexBuffer: Buffer, indexCount: UInt32, height: Int) {
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.height = height
    }
}

/// Draws chunks lit by the sun and fading into the sky with distance.
///
/// Positions are relative to an anchor near the camera, a whole number of
/// meters, so that floats stay precise however far from the origin the
/// camera goes: each chunk's mesh is relative to its corner, and its corner's
/// offset from the anchor comes in a per-instance vertex buffer.
@MainActor
final class ChunkRenderer {
    struct Uniforms {
        var viewProjection: Matrix4x4<Float>
        /// The direction sunlight travels, and the ambient light.
        var light: Vector4<Float>
        /// The focus's x and z, and where fog starts and ends, from it.
        var fog: Vector4<Float>
        var sky: Vector4<Float>
    }

    private let device: Device
    private let queue: Queue
    private let pipeline: RenderPipeline
    private let uniformBuffer: Buffer
    private let bindGroup: BindGroup
    private var offsetBuffer: Buffer
    private var offsetCapacity = 0

    init(device: Device, format: TextureFormat, depthFormat: TextureFormat) throws {
        self.device = device
        queue = device.getQueue()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            viewProjection: mat4x4f,
                            light: vec4f,
                            fog: vec4f,
                            sky: vec4f,
                        }

                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;

                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) color: vec3f,
                            @location(1) world: vec3f,
                        }

                        @vertex
                        fn vertexMain(
                            @location(0) position: vec3f,
                            @location(1) packed: vec4f,
                            @location(2) offset: vec3f
                        ) -> VertexOutput {
                            let world = position + offset;
                            var normal: vec3f;
                            switch u32(round(packed.a * 255.0)) {
                                case 0u: { normal = vec3f(1.0, 0.0, 0.0); }
                                case 1u: { normal = vec3f(-1.0, 0.0, 0.0); }
                                case 2u: { normal = vec3f(0.0, 1.0, 0.0); }
                                case 3u: { normal = vec3f(0.0, -1.0, 0.0); }
                                case 4u: { normal = vec3f(0.0, 0.0, 1.0); }
                                default: { normal = vec3f(0.0, 0.0, -1.0); }
                            }
                            let ambient = uniforms.light.w;
                            let sun = max(dot(normal, -uniforms.light.xyz), 0.0);
                            // Light from the sky above, on top faces most.
                            let skyLight = 0.5 + 0.5 * normal.y;
                            // Darker near the ground, where the streets are
                            // shaded.
                            let street = mix(0.8, 1.0, clamp(world.y / 16.0, 0.0, 1.0));
                            let shade = (ambient * skyLight + (1.0 - ambient) * sun * 0.85 + 0.15) * street;
                            var output: VertexOutput;
                            output.position = uniforms.viewProjection * vec4f(world, 1.0);
                            output.color = packed.rgb * shade;
                            output.world = world;
                            return output;
                        }

                        @fragment
                        fn fragmentMain(
                            @location(0) color: vec3f,
                            @location(1) world: vec3f
                        ) -> @location(0) vec4f {
                            let distance = length(world.xz - uniforms.fog.xy);
                            let fog = smoothstep(uniforms.fog.z, uniforms.fog.w, distance);
                            return vec4f(mix(color, uniforms.sky.rgb, fog), 1.0);
                        }
                        """
                ),
                label: "chunks"
            )
        )
        let uniformSize = UInt64(MemoryLayout<Uniforms>.size)
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "chunk uniforms",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, minBindingSize: uniformSize))
                ]))
        uniformBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(label: "chunk uniforms", usage: [.uniform, .copyDst], size: uniformSize))
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "chunk uniforms", layout: bindGroupLayout,
                entries: [BindGroupEntry(binding: 0, buffer: uniformBuffer, offset: 0, size: uniformSize)]))
        offsetBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(label: "chunk offsets", usage: [.vertex, .copyDst], size: 16))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "chunks",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "chunks", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: UInt64(ChunkMesh.wordsPerVertex * 4),
                            attributes: [
                                VertexAttribute(format: .float32x3, offset: 0, shaderLocation: 0),
                                VertexAttribute(format: .unorm8x4, offset: 12, shaderLocation: 1),
                            ]
                        ),
                        VertexBufferLayout(
                            stepMode: .instance,
                            arrayStride: 16,
                            attributes: [VertexAttribute(format: .float32x3, offset: 0, shaderLocation: 2)]
                        ),
                    ]
                ),
                primitive: PrimitiveState(topology: .triangleList, frontFace: .ccw, cullMode: .back),
                depthStencil: DepthStencilState(format: depthFormat, depthWriteEnabled: true, depthCompare: .less),
                fragment: FragmentState(
                    module: shaderModule,
                    entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format)]
                )
            )
        )
    }

    /// Uploads `mesh`, or returns nil for an empty one.
    func upload(_ mesh: ChunkMesh, height: Int) throws -> GPUChunk? {
        guard !mesh.isEmpty else { return nil }
        let vertexBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "chunk vertices", usage: [.vertex, .copyDst], size: UInt64(mesh.vertices.count * 4)))
        mesh.vertices.withUnsafeBytes { queue.writeBuffer(vertexBuffer, bufferOffset: 0, data: $0) }
        let indexBuffer = try device.createBuffer(
            descriptor: BufferDescriptor(
                label: "chunk indices", usage: [.index, .copyDst], size: UInt64(mesh.indices.count * 4)))
        mesh.indices.withUnsafeBytes { queue.writeBuffer(indexBuffer, bufferOffset: 0, data: $0) }
        return GPUChunk(
            vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, indexCount: UInt32(mesh.indices.count),
            height: height)
    }

    /// Records `chunks`, each at its corner's offset from the anchor, into
    /// `pass`.
    func draw(
        _ chunks: [(chunk: GPUChunk, offset: Vector3<Float>)], uniforms: Uniforms, into pass: RenderPassEncoder
    ) throws {
        guard !chunks.isEmpty else { return }
        withUnsafeBytes(of: uniforms) { queue.writeBuffer(uniformBuffer, bufferOffset: 0, data: $0) }
        if chunks.count > offsetCapacity {
            offsetCapacity = max(chunks.count, offsetCapacity * 2, 256)
            offsetBuffer = try device.createBuffer(
                descriptor: BufferDescriptor(
                    label: "chunk offsets", usage: [.vertex, .copyDst], size: UInt64(offsetCapacity * 16)))
        }
        var offsets = [Float](repeating: 0, count: chunks.count * 4)
        for (index, entry) in chunks.enumerated() {
            offsets[index * 4] = entry.offset.x
            offsets[index * 4 + 1] = entry.offset.y
            offsets[index * 4 + 2] = entry.offset.z
        }
        offsets.withUnsafeBytes { queue.writeBuffer(offsetBuffer, bufferOffset: 0, data: $0) }

        pass.setPipeline(pipeline)
        pass.setBindGroup(groupIndex: 0, group: bindGroup)
        for (index, entry) in chunks.enumerated() {
            let chunk = entry.chunk
            pass.setVertexBuffer(
                slot: 0, buffer: chunk.vertexBuffer, offset: 0, size: UInt64(chunk.indexCount / 6 * 4 * 16))
            pass.setVertexBuffer(slot: 1, buffer: offsetBuffer, offset: UInt64(index * 16), size: 16)
            pass.setIndexBuffer(buffer: chunk.indexBuffer, format: .uint32, offset: 0, size: UInt64(chunk.indexCount) * 4)
            pass.drawIndexed(indexCount: chunk.indexCount, instanceCount: 1, firstIndex: 0, baseVertex: 0, firstInstance: 0)
        }
    }
}
