import Dawn

/// A layer drawn where it was recorded, faded, blurred, or with a shadow
/// under it: what is drawn of content as one, with effects on it.
enum Filter: DrawingKind {
    struct Item {
        var layer: Layer
        /// Where what is in the layer is, in pixels.
        var rectangle: Rect
        var opacity: Float = 1
        /// How far what is in the layer is blurred, in points.
        var blur: Float = 0
        var shadow: Shadow?
    }

    /// What is in the layer, blurred `radius` points far, in `color`, `x` and
    /// `y` points off, under it: a shadow, or a glow when it is light.
    struct Shadow {
        var color: Color
        var radius: Float
        var x: Float = 0
        var y: Float = 0
    }

    struct Planned {
        fileprivate var layer: TextureView
        fileprivate var blur: GaussianBlur.Blur?
        fileprivate var shadow: GaussianBlur.Blur?
        fileprivate var bindGroup: BindGroup
        fileprivate var offset: UInt32
    }

    typealias Resource = FilterResource

    static func prepare(_ items: [Item], resource: FilterResource, in context: PrepareContext) throws -> [Planned] {
        try items.map { try resource.prepare($0, in: context) }
    }

    // The layer, blurred and its shadow blurred, before what it is drawn into.
    static func encodeAhead(_ prepared: [Planned], resource: FilterResource, in context: AheadContext) throws {
        for prepared in prepared {
            for blur in [prepared.blur, prepared.shadow].compactMap({ $0 }) {
                try resource.blur.encode(blur, of: prepared.layer, encoder: context.encoder)
            }
        }
    }

    static func encode(_ prepared: [Planned], resource: FilterResource, in context: EncodeContext) throws {
        context.pass.setPipeline(resource.pipeline)
        for prepared in prepared {
            context.pass.setBindGroup(groupIndex: 0, group: prepared.bindGroup, dynamicOffsets: [prepared.offset])
            context.pass.draw(vertexCount: 4, instanceCount: 1, firstVertex: 0, firstInstance: 0)
        }
    }
}

final class FilterResource: MadeGraphicsResource {
    let blur: GaussianBlur
    let pipeline: RenderPipeline
    private let device: Device
    private unowned let compositor: Compositor
    private let slots: UniformSlots
    private let layout: BindGroupLayout

    init(compositor: Compositor) throws {
        let device = compositor.device
        self.device = device
        self.compositor = compositor
        blur = try compositor.resource(GaussianBlur.self)
        slots = try UniformSlots(device: device, label: "filter")
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            // Where it draws and what is drawn into, in pixels.
                            rectangle: vec4f,
                            size: vec2f,
                            opacity: f32,
                            blurs: f32,
                            shadowColor: vec4f,
                            shadowOffset: vec2f,
                            shadows: f32,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;
                        @group(0) @binding(1) var layer: texture_2d<f32>;
                        @group(0) @binding(2) var blurred: texture_2d<f32>;
                        @group(0) @binding(3) var shadow: texture_2d<f32>;
                        @group(0) @binding(4) var linear: sampler;

                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let pixel = (uniforms.rectangle.xy + corner * uniforms.rectangle.zw) / uniforms.size;
                            return vec4f(pixel.x * 2.0 - 1.0, 1.0 - pixel.y * 2.0, 0.0, 1.0);
                        }

                        // What is in the layer, or it blurred, over its shadow, faded,
                        // premultiplied by its alpha as the layer is.
                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            let size = uniforms.size;
                            let sharp = textureLoad(layer, vec2i(floor(position.xy)), 0);
                            let soft = textureSample(blurred, linear, position.xy / size);
                            let content = select(sharp, soft, uniforms.blurs > 0.5);
                            let coverage = textureSample(shadow, linear, (position.xy - uniforms.shadowOffset) / size).a;
                            let color = uniforms.shadowColor;
                            let under = vec4f(color.rgb * color.a, color.a) * coverage * uniforms.shadows;
                            return (content + under * (1.0 - content.a)) * uniforms.opacity;
                        }
                        """),
                label: "filter"))
        func texture(_ binding: UInt32) -> BindGroupLayoutEntry {
            BindGroupLayoutEntry(
                binding: binding, visibility: .fragment,
                texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`))
        }
        layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "filter",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, hasDynamicOffset: true, minBindingSize: 64)),
                    texture(1), texture(2), texture(3),
                    BindGroupLayoutEntry(binding: 4, visibility: .fragment, sampler: SamplerBindingLayout(type: .filtering)),
                ]))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "filter",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "filter", bindGroupLayouts: [layout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                primitive: PrimitiveState(topology: .triangleStrip),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: compositor.format, blend: .premultipliedAlphaBlending)])))
    }

    func beginFrame() {
        slots.reset()
    }

    fileprivate func prepare(_ item: Filter.Item, in context: PrepareContext) throws -> Filter.Planned {
        let scale = compositor.scale
        let layer = context.texture(of: item.layer)
        let r = item.rectangle
        let blurRadius = item.blur * scale
        let contentBlur = blurRadius > 0 ? try blur.plan(r, radius: blurRadius, in: context) : nil
        let shadowBlur = try item.shadow.map { try blur.plan(r, radius: $0.radius * scale, in: context) }

        // Where it draws: what is in the layer, as far as it is blurred, and
        // its shadow, as far as that is.
        func grown(_ rect: Rect, by amount: Float, x: Float = 0, y: Float = 0) -> Rect {
            Rect(x: rect.x + x - amount, y: rect.y + y - amount, width: rect.width + amount * 2, height: rect.height + amount * 2)
        }
        var region = grown(r, by: blurRadius * 2)
        if let shadow = item.shadow {
            let reach = grown(r, by: shadow.radius * scale * 2, x: shadow.x * scale, y: shadow.y * scale)
            let left = min(region.x, reach.x)
            let top = min(region.y, reach.y)
            region = Rect(
                x: left, y: top, width: max(region.x + region.width, reach.x + reach.width) - left,
                height: max(region.y + region.height, reach.y + reach.height) - top)
        }

        let shadow = item.shadow ?? Filter.Shadow(color: Color(r: 0, g: 0, b: 0, a: 0), radius: 0)
        let offset = slots.write(
            [
                region.x, region.y, region.width, region.height, context.width, context.height, item.opacity,
                contentBlur == nil ? 0 : 1, Float(shadow.color.r), Float(shadow.color.g), Float(shadow.color.b),
                Float(shadow.color.a), shadow.x * scale, shadow.y * scale, item.shadow == nil ? 0 : 1, 0,
            ], queue: context.queue)
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "filter", layout: layout,
                entries: [
                    BindGroupEntry(binding: 0, buffer: slots.buffer, size: 64),
                    BindGroupEntry(binding: 1, textureView: layer),
                    BindGroupEntry(binding: 2, textureView: contentBlur.map { blur.result(of: $0) } ?? layer),
                    BindGroupEntry(binding: 3, textureView: shadowBlur.map { blur.result(of: $0) } ?? layer),
                    BindGroupEntry(binding: 4, sampler: blur.sampler),
                ]))
        return Filter.Planned(layer: layer, blur: contentBlur, shadow: shadowBlur, bindGroup: bindGroup, offset: offset)
    }
}

/// Content drawn into a layer of its own, which `Filter` draws with effects.
struct Filtered: PrimitiveView {
    var content: any View
    var opacity: Float = 1
    var blur: Float = 0
    var shadow: Filter.Shadow?

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [FilteredNode(content: context.resolveOne(content), opacity: opacity, blur: blur, shadow: shadow)]
    }
}

struct FilteredNode: Node {
    var content: any Node
    var opacity: Float
    var blur: Float
    var shadow: Filter.Shadow?

    func size(proposedWidth: Float?, in renderer: Compositor) -> (width: Float, height: Float) {
        content.size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: Compositor) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        let layer = try renderer.layer {
            try content.draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
        }
        renderer.draw(
            Filter.self,
            Filter.Item(
                layer: layer, rectangle: Rect(x: x, y: y, width: size.width, height: size.height).scaled(by: renderer.scale),
                opacity: opacity, blur: blur, shadow: shadow))
    }
}

extension View {
    /// The view drawn as one, `opacity` opaque: where what is in it overlaps,
    /// what is under does not show through.
    func opacity(_ opacity: Float) -> Filtered {
        Filtered(content: self, opacity: opacity)
    }

    /// The view blurred `radius` points far.
    func blur(radius: Float) -> Filtered {
        Filtered(content: self, blur: radius)
    }

    /// The view over its shape blurred `radius` points far in `color`, `x`
    /// and `y` points off: a shadow, or a glow when it is light.
    func shadow(color: Color, radius: Float, x: Float = 0, y: Float = 0) -> Filtered {
        Filtered(content: self, shadow: Filter.Shadow(color: color, radius: radius, x: x, y: y))
    }
}
