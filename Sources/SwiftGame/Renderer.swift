import Dawn
import VectorMath

/// The triangles of a frame, in field coordinates with the origin at the top
/// left, drawn in the order they are appended.
struct Batch {
    // Each vertex is a position in clip space, a position in the shape's own
    // space and a color.
    static let floatsPerVertex = 8

    private(set) var vertices: [Float] = []

    var vertexCount: Int {
        vertices.count / Self.floatsPerVertex
    }

    /// A rectangle from its top-left corner to its bottom-right one, in a
    /// color with each component from 0 to 1, not premultiplied.
    mutating func appendRect(from topLeft: Vector2<Float>, to bottomRight: Vector2<Float>, color: Vector4<Float>) {
        appendQuad(from: topLeft, to: bottomRight, local: 0, color: color)
    }

    /// A ball is a square whose corners the fragment shader discards.
    mutating func appendBall(center: Vector2<Float>, radius: Float, color: Vector4<Float>) {
        appendQuad(from: center - radius, to: center + radius, local: 1, color: color)
    }

    // Rectangles stay at 0 in their own space; balls span -1...1.
    private mutating func appendQuad(
        from topLeft: Vector2<Float>, to bottomRight: Vector2<Float>, local: Float, color: Vector4<Float>
    ) {
        // Clip space has y up.
        let topLeft = topLeft / fieldSize * Vector2(2, -2) + Vector2(-1, 1)
        let bottomRight = bottomRight / fieldSize * Vector2(2, -2) + Vector2(-1, 1)
        let corners: [(position: Vector2<Float>, local: Vector2<Float>)] = [
            (topLeft, Vector2(-local, local)),
            (Vector2(bottomRight.x, topLeft.y), Vector2(local, local)),
            (Vector2(topLeft.x, bottomRight.y), Vector2(-local, -local)),
            (Vector2(bottomRight.x, topLeft.y), Vector2(local, local)),
            (bottomRight, Vector2(local, -local)),
            (Vector2(topLeft.x, bottomRight.y), Vector2(-local, -local)),
        ]
        for corner in corners {
            vertices += [corner.position.x, corner.position.y, corner.local.x, corner.local.y]
            vertices += [color.r, color.g, color.b, color.a]
        }
    }
}

/// Draws batches with one render pipeline, through a vertex buffer that grows
/// to fit the largest batch.
@MainActor
final class Renderer {
    private let device: Device
    private let queue: Queue
    private let pipeline: RenderPipeline
    private var vertexBuffer: Buffer?
    private var vertexBufferSize: UInt64 = 0

    init(device: Device, format: TextureFormat) throws {
        self.device = device
        queue = device.getQueue()
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) local: vec2f,
                            @location(1) color: vec4f,
                        }

                        @vertex
                        fn vertexMain(
                            @location(0) position: vec2f,
                            @location(1) local: vec2f,
                            @location(2) color: vec4f
                        ) -> VertexOutput {
                            var output: VertexOutput;
                            output.position = vec4f(position, 0.0, 1.0);
                            output.local = local;
                            output.color = color;
                            return output;
                        }

                        @fragment
                        fn fragmentMain(
                            @location(0) local: vec2f,
                            @location(1) color: vec4f
                        ) -> @location(0) vec4f {
                            if (dot(local, local) > 1.0) {
                                discard;
                            }
                            return color;
                        }
                        """
                ),
                label: "shapes"
            )
        )
        let floatSize = UInt64(MemoryLayout<Float>.stride)
        let blend = BlendComponent(
            operation: .add, srcFactor: .srcAlpha, dstFactor: .oneMinusSrcAlpha)
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "shapes",
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: UInt64(Batch.floatsPerVertex) * floatSize,
                            attributes: [
                                VertexAttribute(format: .float32x2, offset: 0, shaderLocation: 0),
                                VertexAttribute(
                                    format: .float32x2, offset: 2 * floatSize, shaderLocation: 1),
                                VertexAttribute(
                                    format: .float32x4, offset: 4 * floatSize, shaderLocation: 2),
                            ]
                        )
                    ]
                ),
                primitive: PrimitiveState(topology: .triangleList),
                fragment: FragmentState(
                    module: shaderModule,
                    entryPoint: "fragmentMain",
                    targets: [
                        ColorTargetState(
                            format: format,
                            blend: BlendState(
                                color: blend,
                                alpha: BlendComponent(
                                    operation: .add, srcFactor: .one,
                                    dstFactor: .oneMinusSrcAlpha)
                            )
                        )
                    ]
                )
            )
        )
    }

    /// Clears the surface's current texture to `background`, draws `batch` and
    /// presents it.
    func draw(_ batch: Batch, background: Vector4<Float>, to surface: Surface) throws {
        let byteCount = UInt64(batch.vertices.count * MemoryLayout<Float>.stride)
        if byteCount > vertexBufferSize {
            // Grow by powers of two, so that a growing batch reallocates rarely.
            var size = max(vertexBufferSize, 4096)
            while size < byteCount {
                size *= 2
            }
            vertexBuffer = try device.createBuffer(
                descriptor: BufferDescriptor(
                    label: "shape vertices", usage: [.copyDst, .vertex], size: size)
            )
            vertexBufferSize = size
        }
        if byteCount > 0, let vertexBuffer {
            batch.vertices.withUnsafeBytes { data in
                queue.writeBuffer(vertexBuffer, bufferOffset: 0, data: data)
            }
        }

        let texture = try surface.getCurrentTexture()
        let view = try texture.createView()
        let encoder = try device.createCommandEncoder()
        let pass = try encoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                colorAttachments: [
                    RenderPassColorAttachment(
                        view: view,
                        loadOp: .clear,
                        storeOp: .store,
                        clearValue: Color(
                            r: Double(background.r), g: Double(background.g),
                            b: Double(background.b), a: Double(background.a))
                    )
                ]
            )
        )
        if byteCount > 0, let vertexBuffer {
            pass.setPipeline(pipeline)
            pass.setVertexBuffer(slot: 0, buffer: vertexBuffer, offset: 0, size: byteCount)
            pass.draw(
                vertexCount: UInt32(batch.vertexCount), instanceCount: 1, firstVertex: 0,
                firstInstance: 0)
        }
        pass.end()
        queue.submit([try encoder.finish()])
        try surface.present()
    }
}
