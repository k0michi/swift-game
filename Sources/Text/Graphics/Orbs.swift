import Dawn

/// Circles of colour that drift over squares, over the whole of what is drawn
/// into: a background that moves, for what blurs it to show.
enum Orbs: DrawingKind {
    struct Item {
        var time: Double
    }

    typealias Resource = OrbsResource

    static func prepare(_ items: [Item], resource: OrbsResource, in context: PrepareContext) throws -> [UInt32] {
        items.map { resource.uniforms(for: $0, in: context) }
    }

    static func encode(_ prepared: [UInt32], resource: OrbsResource, in context: EncodeContext) throws {
        context.pass.setPipeline(resource.pipeline)
        for offset in prepared {
            context.pass.setBindGroup(groupIndex: 0, group: resource.bindGroup, dynamicOffsets: [offset])
            context.pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
        }
    }
}

final class OrbsResource: MadeGraphicsResource {
    let pipeline: RenderPipeline
    let bindGroup: BindGroup
    private let slots: UniformSlots

    init(compositor: Compositor) throws {
        let device = compositor.device
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            size: vec2f,
                            time: f32,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;

                        // One triangle over the whole of it.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
                            return vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
                        }

                        // Circles with hard edges over squares, so that what
                        // blurs it shows where it does and nowhere else.
                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            let size = uniforms.size;
                            let t = uniforms.time;
                            let square = floor(position.xy / (min(size.x, size.y) / 16.0));
                            let checker = (i32(square.x) + i32(square.y)) & 1;
                            var color = select(vec3f(0.07, 0.07, 0.1), vec3f(0.12, 0.12, 0.16), checker == 1);
                            let colors = array<vec3f, 4>(
                                vec3f(0.95, 0.35, 0.3), vec3f(0.25, 0.55, 1.0), vec3f(0.3, 0.85, 0.5), vec3f(0.85, 0.4, 0.95));
                            for (var i = 0; i < 4; i += 1) {
                                let phase = f32(i) * 1.7;
                                let center = size * (0.5 + 0.35 * vec2f(sin(t * 0.5 + phase), cos(t * 0.37 + phase * 1.3)));
                                let reach = min(size.x, size.y) * 0.12;
                                let inside = clamp(reach - length(position.xy - center) + 0.5, 0.0, 1.0);
                                color = mix(color, colors[i], inside);
                            }
                            return vec4f(color, 1.0);
                        }
                        """),
                label: "orbs"))
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "orbs",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: .fragment,
                        buffer: BufferBindingLayout(type: .uniform, hasDynamicOffset: true, minBindingSize: 16))
                ]))
        slots = try UniformSlots(device: device, label: "orbs")
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "orbs", layout: bindGroupLayout,
                entries: [BindGroupEntry(binding: 0, buffer: slots.buffer, size: 16)]))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "orbs",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "orbs", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: compositor.format)])))
    }

    func beginFrame() {
        slots.reset()
    }

    fileprivate func uniforms(for item: Orbs.Item, in context: PrepareContext) -> UInt32 {
        slots.write(
            [context.width, context.height, Float(item.time.truncatingRemainder(dividingBy: 1000)), 0],
            queue: context.queue)
    }
}
