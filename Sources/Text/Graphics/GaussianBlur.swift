import Dawn

/// Blurs a region of a texture as big as what is drawn into, for any kind
/// that blurs: at half the size, the region is scaled down, blurred across,
/// then down. A blur is planned in a kind's prepare, which writes its
/// uniforms and sets aside textures for it, and encoded in passes of its own
/// before the kind draws what it blurred.
final class GaussianBlur: MadeGraphicsResource {
    struct Blur {
        fileprivate let offsets: [UInt32]
        fileprivate let working: Int
    }

    private let device: Device
    private let format: TextureFormat
    private let slots: UniformSlots
    private let layout: BindGroupLayout
    let sampler: Sampler
    private let scaleDown: RenderPipeline
    private let blurPass: RenderPipeline
    // Pairs of textures at half the size, one for each blur of the frame,
    // blurred from one into the other.
    private var working: (pairs: [(TextureView, TextureView)], width: UInt32, height: UInt32) = ([], 0, 0)
    private var used = 0

    init(compositor: Compositor) throws {
        let device = compositor.device
        self.device = device
        format = compositor.format
        slots = try UniformSlots(device: device, label: "blur")
        sampler = try device.createSampler(
            descriptor: SamplerDescriptor(
                label: "blur", addressModeU: .clampToEdge, addressModeV: .clampToEdge, addressModeW: .clampToEdge,
                magFilter: .linear, minFilter: .linear, mipmapFilter: .nearest))
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            // The region and what it is in, in pixels.
                            region: vec4f,
                            size: vec2f,
                            radius: f32,
                            // Which way a pass blurs.
                            direction: vec2f,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;
                        @group(0) @binding(1) var source: texture_2d<f32>;
                        @group(0) @binding(2) var linear: sampler;

                        // The region, at half the size.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let pixel = (uniforms.region.xy + corner * uniforms.region.zw) / uniforms.size;
                            return vec4f(pixel.x * 2.0 - 1.0, 1.0 - pixel.y * 2.0, 0.0, 1.0);
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
                        """),
                label: "blur"))
        layout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "blur",
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
            descriptor: PipelineLayoutDescriptor(label: "blur", bindGroupLayouts: [layout]))
        let format = compositor.format
        func pipeline(_ fragment: String) throws -> RenderPipeline {
            try device.createRenderPipeline(
                descriptor: RenderPipelineDescriptor(
                    label: "blur", layout: pipelineLayout,
                    vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                    primitive: PrimitiveState(topology: .triangleStrip),
                    fragment: FragmentState(
                        module: shaderModule, entryPoint: fragment, targets: [ColorTargetState(format: format)])))
        }
        scaleDown = try pipeline("fragmentScaleDown")
        blurPass = try pipeline("fragmentBlur")
    }

    func beginFrame() {
        slots.reset()
        used = 0
    }

    /// Plans a blur `radius` pixels far of `region`, in pixels, with as much
    /// around it as the blur reaches.
    func plan(_ region: Rect, radius: Float, in context: PrepareContext) throws -> Blur {
        let margin = radius * 2
        let region = Rect(
            x: region.x - margin, y: region.y - margin, width: region.width + margin * 2,
            height: region.height + margin * 2)
        let directions: [(Float, Float)] = [(0, 0), (1, 0), (0, 1)]
        let offsets = directions.map { direction in
            slots.write(
                [
                    region.x, region.y, region.width, region.height, context.width, context.height, radius, 0,
                    direction.0, direction.1, 0, 0,
                ], queue: context.queue)
        }
        try reserve(width: UInt32(context.width / 2), height: UInt32(context.height / 2))
        used += 1
        return Blur(offsets: offsets, working: used - 1)
    }

    /// Encodes `blur` of `source`.
    func encode(_ blur: Blur, of source: TextureView, encoder: CommandEncoder) throws {
        let (a, b) = working.pairs[blur.working]
        let passes = [(scaleDown, source, a, blur.offsets[0]), (blurPass, a, b, blur.offsets[1]), (blurPass, b, a, blur.offsets[2])]
        for (pipeline, source, destination, offset) in passes {
            let pass = try encoder.beginRenderPass(
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

    /// What `blur` is drawn into, at half the size, to sample with `sampler`.
    func result(of blur: Blur) -> TextureView {
        working.pairs[blur.working].0
    }

    private func bindGroup(_ source: TextureView) throws -> BindGroup {
        try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "blur", layout: layout,
                entries: [
                    BindGroupEntry(binding: 0, buffer: slots.buffer, size: 64),
                    BindGroupEntry(binding: 1, textureView: source),
                    BindGroupEntry(binding: 2, sampler: sampler),
                ]))
    }

    private func reserve(width: UInt32, height: UInt32) throws {
        if working.width != width || working.height != height {
            working = ([], width, height)
        }
        func texture() throws -> TextureView {
            try device.createTexture(
                descriptor: TextureDescriptor(
                    label: "blur", usage: [.renderAttachment, .textureBinding], dimension: .`2D`,
                    size: Extent3D(width: max(width, 1), height: max(height, 1), depthOrArrayLayers: 1), format: format)
            ).createView()
        }
        while working.pairs.count <= used {
            working.pairs.append((try texture(), try texture()))
        }
    }
}

extension BlendState {
    /// Colours premultiplied by their alpha, as a layer's are, drawn over
    /// what is there.
    static var premultipliedAlphaBlending: BlendState {
        BlendState(
            color: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .oneMinusSrcAlpha),
            alpha: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .oneMinusSrcAlpha))
    }
}
