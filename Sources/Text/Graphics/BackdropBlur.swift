import Dawn

/// What is under a rectangle, blurred. What is drawn over it, a colour to
/// tint it with or what is in it, is drawn by other kinds. It reads what has
/// been drawn, so the pass ends before it, and blurs what is under it, which
/// it draws into the rectangle.
enum BackdropBlur: DrawingKind {
    struct Item {
        var rectangle: Rect
        /// How far the blur reaches, in points.
        var radius: Float
    }

    struct Planned {
        var blur: GaussianBlur.Blur
        var offset: UInt32
    }

    typealias Resource = BackdropBlurResource

    static var readsBackdrop: Bool { true }

    static func prepare(_ items: [Item], resource: BackdropBlurResource, in context: PrepareContext) throws -> [Planned] {
        try items.map { try resource.prepare($0, in: context) }
    }

    static func encodeOffscreen(
        _ prepared: [Planned], resource: BackdropBlurResource, in context: OffscreenContext
    ) throws {
        for prepared in prepared {
            try resource.blur.encode(prepared.blur, of: context.backdrop, encoder: context.encoder)
        }
    }

    static func encode(_ prepared: [Planned], resource: BackdropBlurResource, in context: EncodeContext) throws {
        for prepared in prepared {
            try resource.draw(prepared, in: context)
        }
    }
}

final class BackdropBlurResource: MadeGraphicsResource {
    let blur: GaussianBlur
    private let device: Device
    private unowned let compositor: Compositor
    private let slots: UniformSlots
    private let layout: BindGroupLayout
    private let pipeline: RenderPipeline

    init(compositor: Compositor) throws {
        let device = compositor.device
        self.device = device
        self.compositor = compositor
        blur = try compositor.resource(GaussianBlur.self)
        slots = try UniformSlots(device: device, label: "backdrop blur")
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            // The rectangle and what is drawn into, in pixels.
                            rectangle: vec4f,
                            size: vec2f,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;
                        @group(0) @binding(1) var blurred: texture_2d<f32>;
                        @group(0) @binding(2) var linear: sampler;

                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let pixel = (uniforms.rectangle.xy + corner * uniforms.rectangle.zw) / uniforms.size;
                            return vec4f(pixel.x * 2.0 - 1.0, 1.0 - pixel.y * 2.0, 0.0, 1.0);
                        }

                        // The blurred backdrop, in the rectangle.
                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            return textureSample(blurred, linear, position.xy / uniforms.size);
                        }
                        """),
                label: "backdrop blur"))
        layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "backdrop blur",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, hasDynamicOffset: true, minBindingSize: 32)),
                    BindGroupLayoutEntry(
                        binding: 1, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(binding: 2, visibility: .fragment, sampler: SamplerBindingLayout(type: .filtering)),
                ]))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "backdrop blur",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "backdrop blur", bindGroupLayouts: [layout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                primitive: PrimitiveState(topology: .triangleStrip),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: compositor.format)])))
    }

    func beginFrame() {
        slots.reset()
    }

    fileprivate func prepare(_ item: BackdropBlur.Item, in context: PrepareContext) throws -> BackdropBlur.Planned {
        let r = item.rectangle
        return BackdropBlur.Planned(
            blur: try blur.plan(r, radius: item.radius * compositor.scale, in: context),
            offset: slots.write([r.x, r.y, r.width, r.height, context.width, context.height, 0, 0], queue: context.queue))
    }

    fileprivate func draw(_ prepared: BackdropBlur.Planned, in context: EncodeContext) throws {
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "backdrop blur", layout: layout,
                entries: [
                    BindGroupEntry(binding: 0, buffer: slots.buffer, size: 32),
                    BindGroupEntry(binding: 1, textureView: blur.result(of: prepared.blur)),
                    BindGroupEntry(binding: 2, sampler: blur.sampler),
                ]))
        context.pass.setPipeline(pipeline)
        context.pass.setBindGroup(groupIndex: 0, group: bindGroup, dynamicOffsets: [prepared.offset])
        context.pass.draw(vertexCount: 4, instanceCount: 1, firstVertex: 0, firstInstance: 0)
    }
}

extension View {
    /// What is under the view blurred, `radius` points far, under it.
    func backdropBlur(radius: Float) -> Draw<BackdropBlur> {
        Draw(BackdropBlur.self, item: { rectangle in
            BackdropBlur.Item(rectangle: rectangle, radius: radius)
        }) {
            self
        }
    }
}
