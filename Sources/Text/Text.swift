import CNotoSansJP
import Dawn
import FreeType
import GameToolkit
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn

@main
struct Text: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.video])
        defer { withExtendedLifetime(system) {} }
        let window = try createWindow(title: "text", w: 640, h: 360, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        // A third of the window high, in its pixels.
        let image = try rasterize("aあ", pixelHeight: configuration.height / 3)
        let texture = try device.createTexture(
            descriptor: TextureDescriptor(
                usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: image.width, height: image.height, depthOrArrayLayers: 1), format: .r8Unorm))
        image.pixels.withUnsafeBytes { data in
            device.getQueue().writeTexture(
                destination: TexelCopyTextureInfo(texture: texture), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: image.width, rowsPerImage: image.height),
                writeSize: Extent3D(width: image.width, height: image.height, depthOrArrayLayers: 1))
        }
        let origin = try device.createBuffer(
            descriptor: BufferDescriptor(label: "origin", usage: [.uniform, .copyDst], size: 8))

        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @group(0) @binding(0) var text: texture_2d<f32>;
                        @group(0) @binding(1) var<uniform> origin: vec2f;

                        // One triangle that covers the screen.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
                            return vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
                        }

                        // The text's pixels, one to one with the screen's.
                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            let texel = vec2i(floor(position.xy - origin));
                            if (any(texel < vec2i(0)) || any(texel >= vec2i(textureDimensions(text)))) {
                                discard;
                            }
                            return vec4f(1.0, 1.0, 1.0, textureLoad(text, texel, 0).r);
                        }
                        """),
                label: "text"))
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "text",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 1, visibility: .fragment, buffer: BufferBindingLayout(type: .uniform, minBindingSize: 8)),
                ]))
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "text", layout: bindGroupLayout,
                entries: [
                    BindGroupEntry(binding: 0, textureView: try texture.createView()),
                    BindGroupEntry(binding: 1, buffer: origin),
                ]))
        let pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "text",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "text", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: configuration.format, blend: .alphaBlending)])))

        while true {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested { return }
                if event.type == .windowPixelSizeChanged {
                    configuration = (try? configureSurface(surface, device: device, adapter: adapter, window: window)) ?? configuration
                }
            }

            // In the middle, on whole pixels.
            let center: [Float] = [
                Float((Int(configuration.width) - Int(image.width)) / 2),
                Float((Int(configuration.height) - Int(image.height)) / 2),
            ]
            center.withUnsafeBytes { device.getQueue().writeBuffer(origin, bufferOffset: 0, data: $0) }

            if let surfaceTexture = try? surface.getCurrentTexture() {
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try surfaceTexture.createView(), loadOp: .clear, storeOp: .store,
                                clearValue: Color(r: 0.05, g: 0.05, b: 0.08, a: 1))
                        ]))
                pass.setPipeline(pipeline)
                pass.setBindGroup(groupIndex: 0, group: bindGroup)
                pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
                pass.end()
                device.getQueue().submit([try encoder.finish()])
                try surface.present()
            }

            instance.processEvents()
            await nextFrame()
        }
    }

    // One line of text in coverage from 0 to 255, as high as the font's
    // ascender to descender at pixelHeight pixels to the em.
    static func rasterize(_ text: String, pixelHeight: UInt32) throws -> (pixels: [UInt8], width: UInt32, height: UInt32) {
        let library = try initFreeType()
        let face = try newMemoryFace(
            library: library,
            fileBase: Array(UnsafeBufferPointer(start: CNotoSansJP_Regular, count: CNotoSansJP_RegularSize)))
        try setPixelSizes(face: face, pixelWidth: 0, pixelHeight: pixelHeight)
        let ascender = face.size.metrics.ascender / 64
        let height = ascender - face.size.metrics.descender / 64

        var glyphs: [(bitmap: Bitmap, x: Int, y: Int)] = []
        var penX = 0
        for scalar in text.unicodeScalars {
            try loadChar(face: face, charCode: scalar.value, loadFlags: [.render, .targetLight])
            glyphs.append((face.glyph.bitmap, penX + Int(face.glyph.bitmapLeft), ascender - Int(face.glyph.bitmapTop)))
            penX += face.glyph.advance.x / 64
        }

        let width = penX
        var pixels = [UInt8](repeating: 0, count: width * height)
        for (bitmap, left, top) in glyphs {
            for row in 0..<Int(bitmap.rows) {
                for column in 0..<Int(bitmap.width) {
                    let (x, y) = (left + column, top + row)
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    let coverage = bitmap.buffer[row * Int(bitmap.pitch) + column]
                    pixels[y * width + x] = max(pixels[y * width + x], coverage)
                }
            }
        }
        return (pixels, UInt32(width), UInt32(height))
    }
}
