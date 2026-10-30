import Dawn
import VectorMath

/// Flat 2D shapes on a canvas, in points from its top-left corner, drawn in
/// the order they are appended.
public struct ShapeBatch {
    // Each vertex is a position in clip space, a position in the shape's own
    // space and a color.
    static let floatsPerVertex = 8

    /// The size of the canvas, in points.
    public let canvasSize: Vector2<Float>
    private(set) var vertices: [Float] = []

    var vertexCount: Int {
        vertices.count / Self.floatsPerVertex
    }

    public init(canvasSize: Vector2<Float>) {
        self.canvasSize = canvasSize
    }

    /// A rectangle from its top-left corner to its bottom-right one, in a
    /// color with each component from 0 to 1, not premultiplied.
    public mutating func appendRect(from topLeft: Vector2<Float>, to bottomRight: Vector2<Float>, color: Vector4<Float>) {
        appendQuad(from: topLeft, to: bottomRight, local: 0, color: color)
    }

    /// A ball is a square whose corners the fragment shader discards.
    public mutating func appendBall(center: Vector2<Float>, radius: Float, color: Vector4<Float>) {
        appendQuad(from: center - radius, to: center + radius, local: 1, color: color)
    }

    // Rectangles stay at 0 in their own space; balls span -1...1.
    private mutating func appendQuad(
        from topLeft: Vector2<Float>, to bottomRight: Vector2<Float>, local: Float, color: Vector4<Float>
    ) {
        // In scalars, as unoptimized builds, as in the browser, would take
        // far longer over vectors. Clip space has y up.
        let left = topLeft.x / canvasSize.x * 2 - 1
        let right = bottomRight.x / canvasSize.x * 2 - 1
        let top = 1 - topLeft.y / canvasSize.y * 2
        let bottom = 1 - bottomRight.y / canvasSize.y * 2
        let (r, g, b, a) = (color.r, color.g, color.b, color.a)
        vertices += [
            left, top, -local, local, r, g, b, a,
            right, top, local, local, r, g, b, a,
            left, bottom, -local, -local, r, g, b, a,
            right, top, local, local, r, g, b, a,
            right, bottom, local, -local, r, g, b, a,
            left, bottom, -local, -local, r, g, b, a,
        ]
    }
}

/// Draws shape batches into a render pass, with one render pipeline, through
/// a vertex buffer that grows to fit the largest batch.
@MainActor
public final class ShapeRenderer {
    private let device: Device
    private let queue: Queue
    private let pipeline: RenderPipeline
    private let vertexBuffer: GrowingBuffer

    /// A renderer for passes into `format`, and with a depth attachment of
    /// `depthFormat` if there is one, which the shapes neither test nor write.
    public init(device: Device, format: TextureFormat, depthFormat: TextureFormat? = nil) throws {
        self.device = device
        queue = device.getQueue()
        vertexBuffer = GrowingBuffer(device: device, label: "shape vertices", usage: .vertex)
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
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "shapes",
                vertex: VertexState(
                    module: shaderModule,
                    entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex,
                            arrayStride: UInt64(ShapeBatch.floatsPerVertex) * floatSize,
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
                // Over everything drawn in 3D, whatever its depth.
                depthStencil: depthFormat.map {
                    DepthStencilState(format: $0, depthWriteEnabled: false, depthCompare: .always)
                },
                fragment: FragmentState(
                    module: shaderModule,
                    entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format, blend: .alphaBlending)]
                )
            )
        )
    }

    /// Records `batch` into `pass`.
    public func draw(_ batch: ShapeBatch, into pass: RenderPassEncoder) throws {
        guard batch.vertexCount > 0 else { return }
        let buffer = try vertexBuffer.write(batch.vertices, queue: queue)
        pass.setPipeline(pipeline)
        pass.setVertexBuffer(slot: 0, buffer: buffer, offset: 0, size: UInt64(batch.vertices.count * 4))
        pass.draw(vertexCount: UInt32(batch.vertexCount), instanceCount: 1, firstVertex: 0, firstInstance: 0)
    }
}

/// A buffer that grows by powers of two to fit what is written to it, so
/// that it reallocates rarely.
@MainActor
final class GrowingBuffer {
    private let device: Device
    private let label: String
    private let usage: BufferUsage
    private var buffer: Buffer?
    private var size: UInt64 = 0

    init(device: Device, label: String, usage: BufferUsage) {
        self.device = device
        self.label = label
        self.usage = usage
    }

    /// Writes `values` from the start of the buffer, through `queue`.
    func write<Value>(_ values: [Value], queue: Queue) throws -> Buffer {
        let byteCount = UInt64(values.count * MemoryLayout<Value>.stride)
        if byteCount > size || buffer == nil {
            var newSize = max(size, 4096)
            while newSize < byteCount {
                newSize *= 2
            }
            buffer = try device.createBuffer(
                descriptor: BufferDescriptor(label: label, usage: [.copyDst, usage], size: newSize))
            size = newSize
        }
        let buffer = buffer!
        values.withUnsafeBytes { data in
            queue.writeBuffer(buffer, bufferOffset: 0, data: data)
        }
        return buffer
    }
}

extension BlendState {
    /// Colors not premultiplied by their alpha, drawn over what is there.
    public static var alphaBlending: BlendState {
        BlendState(
            color: BlendComponent(operation: .add, srcFactor: .srcAlpha, dstFactor: .oneMinusSrcAlpha),
            alpha: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .oneMinusSrcAlpha))
    }
}
