import Dawn

/// A texture drawn over the whole of what is drawn into, pixel for pixel: how
/// the frame, drawn offscreen, gets onto the surface.
enum PresentKind: DrawingKind {
    typealias Item = TextureView
    typealias Resource = PresentResource

    static func prepare(_ items: [TextureView], resource: PresentResource, in context: PrepareContext) throws -> [BindGroup] {
        try items.map { try resource.bindGroup(for: $0) }
    }

    static func encode(_ prepared: [BindGroup], resource: PresentResource, in context: EncodeContext) throws {
        for bindGroup in prepared {
            context.pass.setPipeline(resource.pipeline)
            context.pass.setBindGroup(groupIndex: 0, group: bindGroup)
            context.pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
        }
    }
}

final class PresentResource: MadeGraphicsResource {
    let pipeline: RenderPipeline
    private let device: Device
    private let layout: BindGroupLayout

    init(compositor: Compositor) throws {
        device = compositor.device
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @group(0) @binding(0) var frame: texture_2d<f32>;

                        // One triangle over the whole of it.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
                            return vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
                        }

                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            return textureLoad(frame, vec2i(floor(position.xy)), 0);
                        }
                        """),
                label: "present"))
        layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "present",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`))
                ]))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "present",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "present", bindGroupLayouts: [layout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain", targets: [ColorTargetState(format: compositor.format)])))
    }

    fileprivate func bindGroup(for view: TextureView) throws -> BindGroup {
        try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "present", layout: layout, entries: [BindGroupEntry(binding: 0, textureView: view)]))
    }
}
