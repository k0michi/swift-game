import Dawn

// A button of the game's own, its face drawn by a shader of its own: a
// rounded rectangle lit from the top, with light sweeping across it and a
// glow around it that pulses, which brightens when the pointer is over it and
// sinks when it is pressed. Its title is drawn over it as any text is.
struct GlowButton: View {
    var title: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Pressable(action: action) { interaction in
            GPUView(
                GlowButtonFace.self,
                parameters: GlowButtonFace.Parameters(
                    color: color, isPressed: interaction.isPressed, isHovered: interaction.isHovered)
            ) {
                Text(title).font(size: 20).padding(horizontal: 26, vertical: 12)
            }
        }
    }
}

final class GlowButtonFace: GPUDrawing {
    struct Parameters {
        var color: Color
        var isPressed: Bool
        var isHovered: Bool
    }

    // How far around the button its glow goes, in points.
    private static let glow: Float = 14

    private let pipeline: RenderPipeline
    private let uniforms: Dawn.Buffer
    private let bindGroup: BindGroup

    init(device: Device, format: TextureFormat) throws {
        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        struct Uniforms {
                            // The button's rectangle and the screen, in pixels.
                            rectangle: vec4f,
                            screen: vec2f,
                            time: f32,
                            pressed: f32,
                            color: vec4f,
                            hovered: f32,
                            scale: f32,
                            glow: f32,
                        }
                        @group(0) @binding(0) var<uniform> uniforms: Uniforms;

                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) pixel: vec2f,
                        }

                        // The rectangle and its glow, in a strip of two triangles.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> VertexOutput {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let margin = uniforms.glow * uniforms.scale;
                            let pixel = uniforms.rectangle.xy - margin + corner * (uniforms.rectangle.zw + margin * 2.0);
                            var output: VertexOutput;
                            output.position = vec4f(
                                pixel.x / uniforms.screen.x * 2.0 - 1.0, 1.0 - pixel.y / uniforms.screen.y * 2.0, 0.0, 1.0);
                            output.pixel = pixel;
                            return output;
                        }

                        // How far `pixel` is outside a rectangle with corners `radius` round.
                        fn distance(pixel: vec2f, rectangle: vec4f, radius: f32) -> f32 {
                            let half = rectangle.zw * 0.5;
                            let corner = abs(pixel - rectangle.xy - half) - half + radius;
                            return length(max(corner, vec2f(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
                        }

                        @fragment
                        fn fragmentMain(@location(0) pixel: vec2f) -> @location(0) vec4f {
                            let scale = uniforms.scale;
                            var rectangle = uniforms.rectangle;
                            rectangle.y += uniforms.pressed * 3.0 * scale;
                            let d = distance(pixel, rectangle, 14.0 * scale);
                            let lit = 1.0 + uniforms.hovered * 0.25 - uniforms.pressed * 0.2;

                            // Around it, a glow that pulses.
                            let pulse = 0.6 + 0.4 * sin(uniforms.time * 3.0);
                            let glow = exp(-max(d, 0.0) / (5.0 * scale)) * pulse * (0.5 + uniforms.hovered * 0.5)
                                * (1.0 - uniforms.pressed * 0.6);
                            var color = vec4f(uniforms.color.rgb * 1.2, glow * 0.8);

                            if (d < 0.0) {
                                // Its face, lighter at the top, with a band of light
                                // sweeping across it, and a rim.
                                let along = (pixel.y - rectangle.y) / rectangle.w;
                                var face = uniforms.color.rgb * mix(1.35, 0.75, along) * lit;
                                let sweep = fract(uniforms.time * 0.4) * (rectangle.z + rectangle.w * 2.0) - rectangle.w;
                                let band = (pixel.x - rectangle.x) + (pixel.y - rectangle.y) * 0.6 - sweep;
                                face += vec3f(0.35) * smoothstep(18.0 * scale, 0.0, abs(band));
                                let rim = smoothstep(-3.0 * scale, -1.0 * scale, d);
                                face = mix(face, vec3f(1.0), rim * 0.55);
                                let edge = clamp(-d, 0.0, 1.0);
                                color = mix(color, vec4f(face, 1.0), edge);
                            }
                            return color;
                        }
                        """),
                label: "glow button"))
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "glow button",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: [.vertex, .fragment],
                        buffer: BufferBindingLayout(type: .uniform, minBindingSize: 64))
                ]))
        uniforms = try device.createBuffer(
            descriptor: BufferDescriptor(label: "glow button", usage: [.uniform, .copyDst], size: 64))
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "glow button", layout: bindGroupLayout, entries: [BindGroupEntry(binding: 0, buffer: uniforms)]))
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "glow button",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "glow button", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                primitive: PrimitiveState(topology: .triangleStrip),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format, blend: .alphaBlending)])))
    }

    func draw(_ parameters: Parameters, in context: GPUDrawContext) throws {
        let color = parameters.color
        let values: [Float] = [
            context.x, context.y, context.width, context.height,
            context.screenWidth, context.screenHeight, Float(context.time.truncatingRemainder(dividingBy: 1000)),
            parameters.isPressed ? 1 : 0,
            Float(color.r), Float(color.g), Float(color.b), Float(color.a),
            parameters.isHovered ? 1 : 0, context.scale, Self.glow, 0,
        ]
        values.withUnsafeBytes { context.device.getQueue().writeBuffer(uniforms, bufferOffset: 0, data: $0) }
        context.pass.setPipeline(pipeline)
        context.pass.setBindGroup(groupIndex: 0, group: bindGroup)
        context.pass.draw(vertexCount: 4, instanceCount: 1, firstVertex: 0, firstInstance: 0)
    }
}
