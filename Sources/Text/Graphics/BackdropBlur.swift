import Dawn

/// What is under a rectangle, blurred. What is drawn over it, a colour to
/// tint it with or what is in it, is drawn by other kinds. It reads what has
/// been drawn, so the pass ends before it. Its work is at half the size: what
/// is under it, with as much around it as the blur reaches, is scaled down,
/// blurred across, then down, and drawn into the rectangle.
enum BackdropBlur: DrawingKind {
    struct Item {
        var rectangle: Rect
        /// How far the blur reaches, in points.
        var radius: Float
    }

    typealias Resource = BackdropBlurResource

    static var readsBackdrop: Bool { true }

    // The offsets of its uniforms for scaling down, blurring across, and
    // blurring down, which drawing it uses too.
    static func prepare(_ items: [Item], resource: BackdropBlurResource, in context: PrepareContext) throws -> [[UInt32]] {
        items.map { resource.uniforms(for: $0, in: context) }
    }

    static func encodeOffscreen(
        _ prepared: [[UInt32]], resource: BackdropBlurResource, in context: OffscreenContext
    ) throws {
        for offsets in prepared {
            try resource.blur(offsets, in: context)
        }
    }

    static func encode(_ prepared: [[UInt32]], resource: BackdropBlurResource, in context: EncodeContext) throws {
        for offsets in prepared {
            try resource.drawBlurred(offsets[0], in: context)
        }
    }
}

final class BackdropBlurResource: MadeGraphicsResource {
    private let device: Device
    private unowned let compositor: Compositor
    private let format: TextureFormat
    private let slots: UniformSlots
    private let layout: BindGroupLayout
    private let sampler: Sampler
    private let scaleDown: RenderPipeline
    private let blurPass: RenderPipeline
    private let composite: RenderPipeline
    // Two textures at half the size, blurred from one into the other.
    private var working: (a: TextureView, b: TextureView, width: UInt32, height: UInt32)?

    init(compositor: Compositor) throws {
        let device = compositor.device
        self.device = device
        self.compositor = compositor
        format = compositor.format
        slots = try UniformSlots(device: device, label: "backdrop blur")
        sampler = try device.createSampler(
            descriptor: SamplerDescriptor(
                label: "backdrop blur", addressModeU: .clampToEdge, addressModeV: .clampToEdge,
                addressModeW: .clampToEdge, magFilter: .linear, minFilter: .linear, mipmapFilter: .nearest))
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            // The shape and what is drawn into, in pixels.
                            rectangle: vec4f,
                            size: vec2f,
                            radius: f32,
                            // Which way a pass blurs, in texels.
                            direction: vec2f,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;
                        @group(0) @binding(1) var source: texture_2d<f32>;
                        @group(0) @binding(2) var linear: sampler;

                        fn clip(pixel: vec2f, size: vec2f) -> vec4f {
                            return vec4f(pixel.x / size.x * 2.0 - 1.0, 1.0 - pixel.y / size.y * 2.0, 0.0, 1.0);
                        }

                        // The shape, with as much around it as the blur reaches, at
                        // half the size.
                        @vertex
                        fn vertexHalf(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let margin = uniforms.radius * 2.0;
                            let pixel = uniforms.rectangle.xy - margin + corner * (uniforms.rectangle.zw + margin * 2.0);
                            return clip(pixel * 0.5, uniforms.size * 0.5);
                        }

                        @fragment
                        fn fragmentScaleDown(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            return textureSample(source, linear, position.xy * 2.0 / uniforms.size);
                        }

                        // Nine samples of a Gaussian, the reach of the blur apart in
                        // all, along the pass's direction.
                        @fragment
                        fn fragmentBlur(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            let half = uniforms.size * 0.5;
                            let uv = position.xy / half;
                            let step = uniforms.direction * (uniforms.radius * 0.5 / 4.0) / half;
                            let weights = array<f32, 5>(0.227, 0.194, 0.121, 0.054, 0.016);
                            var color = textureSample(source, linear, uv) * weights[0];
                            for (var i = 1; i < 5; i += 1) {
                                color += textureSample(source, linear, uv + step * f32(i)) * weights[i];
                                color += textureSample(source, linear, uv - step * f32(i)) * weights[i];
                            }
                            return color;
                        }

                        @vertex
                        fn vertexShape(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            return clip(uniforms.rectangle.xy + corner * uniforms.rectangle.zw, uniforms.size);
                        }

                        // The blurred backdrop, in the rectangle.
                        @fragment
                        fn fragmentShape(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            return textureSample(source, linear, position.xy / uniforms.size);
                        }
                        """),
                label: "backdrop blur"))
        layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "backdrop blur",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, hasDynamicOffset: true, minBindingSize: 64)),
                    BindGroupLayoutEntry(
                        binding: 1, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(binding: 2, visibility: .fragment, sampler: SamplerBindingLayout(type: .filtering)),
                ]))
        let pipelineLayout = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(label: "backdrop blur", bindGroupLayouts: [layout]))
        let format = compositor.format
        func pipeline(_ vertex: String, _ fragment: String, blend: BlendState?) throws -> RenderPipeline {
            try device.createRenderPipeline(
                descriptor: RenderPipelineDescriptor(
                    label: "backdrop blur", layout: pipelineLayout,
                    vertex: VertexState(module: shaderModule, entryPoint: vertex),
                    primitive: PrimitiveState(topology: .triangleStrip),
                    fragment: FragmentState(
                        module: shaderModule, entryPoint: fragment,
                        targets: [ColorTargetState(format: format, blend: blend)])))
        }
        scaleDown = try pipeline("vertexHalf", "fragmentScaleDown", blend: nil)
        blurPass = try pipeline("vertexHalf", "fragmentBlur", blend: nil)
        composite = try pipeline("vertexShape", "fragmentShape", blend: nil)
    }

    func beginFrame() {
        slots.reset()
    }

    fileprivate func uniforms(for item: BackdropBlur.Item, in context: PrepareContext) -> [UInt32] {
        let r = item.rectangle
        let directions: [(Float, Float)] = [(0, 0), (1, 0), (0, 1)]
        return directions.map { direction in
            slots.write(
                [
                    r.x, r.y, r.width, r.height, context.width, context.height, item.radius * compositor.scale, 0, direction.0,
                    direction.1, 0, 0,
                ], queue: context.queue)
        }
    }

    // Scales the backdrop down into one working texture, blurs it across
    // into the other, and down back into the first.
    fileprivate func blur(_ offsets: [UInt32], in context: OffscreenContext) throws {
        let working = try workingTextures(width: UInt32(context.width / 2), height: UInt32(context.height / 2))
        let passes: [(RenderPipeline, TextureView, TextureView, UInt32)] = [
            (scaleDown, context.backdrop, working.a, offsets[0]),
            (blurPass, working.a, working.b, offsets[1]),
            (blurPass, working.b, working.a, offsets[2]),
        ]
        for (pipeline, source, destination, offset) in passes {
            let pass = try context.encoder.beginRenderPass(
                descriptor: RenderPassDescriptor(
                    colorAttachments: [
                        RenderPassColorAttachment(
                            view: destination, loadOp: .clear, storeOp: .store, clearValue: Color(r: 0, g: 0, b: 0, a: 0))
                    ]))
            pass.setPipeline(pipeline)
            pass.setBindGroup(groupIndex: 0, group: try bindGroup(source), dynamicOffsets: [offset])
            pass.draw(vertexCount: 4, instanceCount: 1, firstVertex: 0, firstInstance: 0)
            pass.end()
        }
    }

    fileprivate func drawBlurred(_ offset: UInt32, in context: EncodeContext) throws {
        guard let working else { return }
        context.pass.setPipeline(composite)
        context.pass.setBindGroup(groupIndex: 0, group: try bindGroup(working.a), dynamicOffsets: [offset])
        context.pass.draw(vertexCount: 4, instanceCount: 1, firstVertex: 0, firstInstance: 0)
    }

    private func bindGroup(_ source: TextureView) throws -> BindGroup {
        try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "backdrop blur", layout: layout,
                entries: [
                    BindGroupEntry(binding: 0, buffer: slots.buffer, size: 64),
                    BindGroupEntry(binding: 1, textureView: source),
                    BindGroupEntry(binding: 2, sampler: sampler),
                ]))
    }

    private func workingTextures(width: UInt32, height: UInt32) throws -> (a: TextureView, b: TextureView, width: UInt32, height: UInt32) {
        if let working, working.width == width, working.height == height {
            return working
        }
        func texture() throws -> TextureView {
            try device.createTexture(
                descriptor: TextureDescriptor(
                    label: "backdrop blur", usage: [.renderAttachment, .textureBinding], dimension: .`2D`,
                    size: Extent3D(width: max(width, 1), height: max(height, 1), depthOrArrayLayers: 1), format: format)
            ).createView()
        }
        let working = (try texture(), try texture(), width, height)
        self.working = working
        return working
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
