import Dawn

/// A texture of coverage, 0 to 1, that glyphs and the like are put into as
/// they are first needed, a row at a time, with a white texel in its last
/// corner for solid quads. When it runs out of room, it is emptied at the next
/// frame, and its generation counts up for those who put things in it.
final class TextureAtlas: MadeGraphicsResource {
    static let size = 1024

    let texture: Texture
    let view: TextureView
    private(set) var generation = 0
    private let queue: Queue
    // The row being filled, from its top and as high as its highest image, and
    // how far along it is.
    private var shelf = (x: 0, y: 0, height: 0)
    private var isFull = false

    init(compositor: Compositor) throws {
        queue = compositor.device.getQueue()
        texture = try compositor.device.createTexture(
            descriptor: TextureDescriptor(
                label: "atlas", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(Self.size), height: UInt32(Self.size), depthOrArrayLayers: 1),
                format: .r8Unorm))
        view = try texture.createView()
        [UInt8(255)].withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(
                    texture: texture, origin: Origin3D(x: UInt32(Self.size - 1), y: UInt32(Self.size - 1))),
                data: data, dataLayout: TexelCopyBufferLayout(bytesPerRow: 1, rowsPerImage: 1),
                writeSize: Extent3D(width: 1, height: 1, depthOrArrayLayers: 1))
        }
    }

    /// The middle of the white texel.
    var white: (x: Float, y: Float) {
        (Float(Self.size - 1) + 0.5, Float(Self.size - 1) + 0.5)
    }

    func beginFrame() {
        if isFull {
            shelf = (0, 0, 0)
            isFull = false
            generation += 1
        }
    }

    /// Puts `width` by `height` texels of `pixels`, rows `pitch` bytes apart,
    /// into the atlas, and returns where, or nil if there is no room this
    /// frame.
    func put(width: Int, height: Int, pitch: Int, pixels: [UInt8]) -> (x: Int, y: Int)? {
        if shelf.x + width > Self.size {
            shelf = (0, shelf.y + shelf.height + 1, 0)
        }
        // The last row has the white texel.
        guard shelf.y + height < Self.size - 1 else {
            isFull = true
            return nil
        }
        let origin = (shelf.x, shelf.y)
        shelf = (shelf.x + width + 1, shelf.y, max(shelf.height, height))
        if width > 0, height > 0 {
            pixels.withUnsafeBytes { data in
                queue.writeTexture(
                    destination: TexelCopyTextureInfo(
                        texture: texture, origin: Origin3D(x: UInt32(origin.0), y: UInt32(origin.1))),
                    data: data, dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(pitch), rowsPerImage: UInt32(height)),
                    writeSize: Extent3D(width: UInt32(width), height: UInt32(height), depthOrArrayLayers: 1))
            }
        }
        return origin
    }
}

/// Quads in pixels, each of a color times the coverage of the texels of the
/// atlas it spans: glyphs, and solid rectangles, which span the white texel.
/// All of a group are one draw.
enum QuadKind: DrawingKind {
    struct Item {
        var rectangle: Rect
        var texel: (x: Float, y: Float)
        var texels: (width: Float, height: Float)
        var color: Color
    }

    typealias Resource = QuadResource

    static func prepare(_ items: [Item], resource: QuadResource, in context: PrepareContext) throws -> Range<Int> {
        try resource.append(items, in: context)
    }

    static func encode(_ prepared: Range<Int>, resource: QuadResource, in context: EncodeContext) throws {
        resource.draw(prepared, into: context.pass)
    }
}

final class QuadResource: MadeGraphicsResource {
    private static let floatsPerInstance = 12

    private let device: Device
    private let pipeline: RenderPipeline
    private let bindGroup: BindGroup
    private let screen: Dawn.Buffer
    private var instances: [Float] = []
    private var buffer: Dawn.Buffer?
    private var bufferSize: UInt64 = 0

    init(compositor: Compositor) throws {
        device = compositor.device
        let atlas = try compositor.resource(TextureAtlas.self)
        screen = try device.createBuffer(descriptor: BufferDescriptor(label: "screen", usage: [.uniform, .copyDst], size: 8))
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @group(0) @binding(0) var atlas: texture_2d<f32>;
                        @group(0) @binding(1) var<uniform> screen: vec2f;

                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) texel: vec2f,
                            @location(1) color: vec4f,
                        }

                        // A corner of the quad, in a strip of two triangles.
                        @vertex
                        fn vertexMain(
                            @builtin(vertex_index) index: u32,
                            @location(0) rectangle: vec4f,
                            @location(1) texel: vec2f,
                            @location(2) texels: vec2f,
                            @location(3) color: vec4f
                        ) -> VertexOutput {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let pixel = rectangle.xy + corner * rectangle.zw;
                            var output: VertexOutput;
                            output.position = vec4f(pixel.x / screen.x * 2.0 - 1.0, 1.0 - pixel.y / screen.y * 2.0, 0.0, 1.0);
                            output.texel = texel + corner * texels;
                            output.color = color;
                            return output;
                        }

                        // The atlas's texels, one to one with the screen's pixels.
                        @fragment
                        fn fragmentMain(@location(0) texel: vec2f, @location(1) color: vec4f) -> @location(0) vec4f {
                            return vec4f(color.rgb, color.a * textureLoad(atlas, vec2i(floor(texel)), 0).r);
                        }
                        """),
                label: "quads"))
        let layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "quads",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 1, visibility: .vertex, buffer: BufferBindingLayout(type: .uniform, minBindingSize: 8)),
                ]))
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "quads", layout: layout,
                entries: [BindGroupEntry(binding: 0, textureView: atlas.view), BindGroupEntry(binding: 1, buffer: screen)]))
        let floatSize = UInt64(MemoryLayout<Float>.stride)
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "quads",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "quads", bindGroupLayouts: [layout])),
                vertex: VertexState(
                    module: shaderModule, entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .instance, arrayStride: UInt64(Self.floatsPerInstance) * floatSize,
                            attributes: [
                                VertexAttribute(format: .float32x4, offset: 0, shaderLocation: 0),
                                VertexAttribute(format: .float32x2, offset: 4 * floatSize, shaderLocation: 1),
                                VertexAttribute(format: .float32x2, offset: 6 * floatSize, shaderLocation: 2),
                                VertexAttribute(format: .float32x4, offset: 8 * floatSize, shaderLocation: 3),
                            ])
                    ]),
                primitive: PrimitiveState(topology: .triangleStrip),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: compositor.format, blend: .alphaBlending)])))
    }

    func beginFrame() {
        instances.removeAll(keepingCapacity: true)
    }

    // The frame's groups, one after another in one buffer, which is written
    // as each is prepared.
    fileprivate func append(_ items: [QuadKind.Item], in context: PrepareContext) throws -> Range<Int> {
        let first = instances.count / Self.floatsPerInstance
        for item in items {
            let r = item.rectangle
            instances += [
                r.x, r.y, r.width, r.height, item.texel.x, item.texel.y, item.texels.width, item.texels.height,
                Float(item.color.r), Float(item.color.g), Float(item.color.b), Float(item.color.a),
            ]
        }
        let byteCount = UInt64(instances.count * MemoryLayout<Float>.stride)
        if byteCount > bufferSize {
            var size = max(bufferSize, 4096)
            while size < byteCount { size *= 2 }
            buffer = try device.createBuffer(descriptor: BufferDescriptor(label: "quads", usage: [.vertex, .copyDst], size: size))
            bufferSize = size
            // A new buffer holds nothing of the groups before.
            instances.withUnsafeBytes { context.queue.writeBuffer(buffer!, bufferOffset: 0, data: $0) }
        } else {
            let offset = first * Self.floatsPerInstance
            instances[offset...].withUnsafeBytes {
                context.queue.writeBuffer(buffer!, bufferOffset: UInt64(offset * MemoryLayout<Float>.stride), data: $0)
            }
        }
        [context.width, context.height].withUnsafeBytes { context.queue.writeBuffer(screen, bufferOffset: 0, data: $0) }
        return first..<instances.count / Self.floatsPerInstance
    }

    fileprivate func draw(_ range: Range<Int>, into pass: RenderPassEncoder) {
        guard !range.isEmpty, let buffer else { return }
        pass.setPipeline(pipeline)
        pass.setBindGroup(groupIndex: 0, group: bindGroup)
        pass.setVertexBuffer(slot: 0, buffer: buffer, offset: 0, size: bufferSize)
        pass.draw(vertexCount: 4, instanceCount: UInt32(range.count), firstVertex: 0, firstInstance: UInt32(range.lowerBound))
    }
}

extension Compositor {
    /// Records a rectangle filled, from `x`, `y` in points, `width` by
    /// `height`, in `color`, which is not premultiplied, on whole pixels.
    func fill(x: Float, y: Float, width: Float, height: Float, color: Color) {
        let left = (x * scale).rounded()
        let top = (y * scale).rounded()
        let white = try! resource(TextureAtlas.self).white
        draw(
            QuadKind.self,
            QuadKind.Item(
                rectangle: Rect(
                    x: left, y: top, width: ((x + width) * scale).rounded() - left,
                    height: ((y + height) * scale).rounded() - top),
                texel: white, texels: (0, 0), color: color))
    }
}
