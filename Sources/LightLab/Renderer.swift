import Dawn
import GameToolkit
import VectorMath

/// What the scene's shaders read each frame.
struct FrameUniforms {
    var viewProjection: Matrix4x4<Float>
    var sunViewProjection: Matrix4x4<Float>
    var sunDirection: Vector4<Float>
    var sunColor: Vector4<Float>
    var skyColor: Vector4<Float>
    var horizonColor: Vector4<Float>
    var groundColor: Vector4<Float>
    var viewDirection: Vector4<Float>
    /// The number of lamps, the exposure, the strength of the sky's light,
    /// and of bloom.
    var params: Vector4<Float>
    var gridSize: Vector4<Float>
    /// Where the eye is, with 1 for a perspective view, whose direction
    /// differs from pixel to pixel, or 0 for `viewDirection` everywhere.
    var eye: Vector4<Float>
    /// The width of a square of the lamps' grid, and how many along x and z.
    var lightGrid: Vector4<Float>
}

/// Draws the scene in light: depth from the sun for its shadows, then the
/// opaque voxels lit by the sun, the sky and the lamps, then glass, into a
/// target of high dynamic range, which bloom spreads and a filmic curve
/// maps to the screen.
@MainActor
final class Renderer {
    static let hdrFormat = TextureFormat.rgba16Float
    static let depthFormat = TextureFormat.depth32Float
    static let shadowMapSize: UInt32 = 4096
    static let bloomLevels = 6
    /// How many texels wide the lamps' texture is, two for each lamp.
    static let lightTextureWidth = 256
    /// How many voxels of the grid a cell of the sky's grid covers each way.
    static let skyCellSize = 4

    private let device: Device
    private let queue: Queue
    private let surfaceFormat: TextureFormat

    private let sceneLayout: BindGroupLayout
    private let shadowPipeline: RenderPipeline
    private let opaquePipeline: RenderPipeline
    private let glassPipeline: RenderPipeline
    private let downPipeline: RenderPipeline
    private let upPipeline: RenderPipeline
    private let compositePipeline: RenderPipeline

    private let frameBuffer: Buffer
    private let materialBuffer: Buffer
    private let lightTexture: Texture
    private let lightTextureHeight: UInt32
    private let settingsBuffer: Buffer
    private let shadowView: TextureView
    private let sceneBindGroup: BindGroup
    private let shadowBindGroup: BindGroup
    private let linearSampler: Sampler

    private struct Mesh {
        var vertices: Buffer
        var indices: Buffer
        var indexCount: UInt32
    }
    private let opaqueMesh: Mesh?
    private let glassMesh: Mesh?
    private var characterMesh: Mesh?

    /// Targets the size of the screen, made again when it changes.
    private struct Targets {
        var width: UInt32
        var height: UInt32
        var hdr: TextureView
        var depth: TextureView
        var bloom: [TextureView]
        var bloomSizes: [(UInt32, UInt32)]
        var downGroups: [BindGroup]
        var upGroups: [BindGroup]
        var compositeGroup: BindGroup
    }
    private var targets: Targets?

    init(device: Device, surfaceFormat: TextureFormat, scene: Scene) throws {
        self.device = device
        let queue = device.getQueue()
        self.queue = queue
        self.surfaceFormat = surfaceFormat

        let sceneModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(nextInChain: ShaderSourceWGSL(code: Shaders.scene), label: "scene"))
        let shadowModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(nextInChain: ShaderSourceWGSL(code: Shaders.shadow), label: "shadow"))
        let postModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(nextInChain: ShaderSourceWGSL(code: Shaders.post), label: "post"))

        func uniformBuffer(_ label: String, size: Int) throws -> Buffer {
            try device.createBuffer(
                descriptor: BufferDescriptor(label: label, usage: [.uniform, .copyDst], size: UInt64(size)))
        }
        frameBuffer = try uniformBuffer("frame", size: MemoryLayout<FrameUniforms>.size)
        materialBuffer = try uniformBuffer("materials", size: 256 * 16)
        settingsBuffer = try uniformBuffer("post settings", size: 16)

        // The sun's shadow map, and the voxels as textures.
        let shadowTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "shadow map", usage: [.renderAttachment, .textureBinding], dimension: .`2D`,
                size: Extent3D(width: Self.shadowMapSize, height: Self.shadowMapSize, depthOrArrayLayers: 1),
                format: Self.depthFormat))
        shadowView = try shadowTexture.createView()
        let grid = scene.grid
        let occupancy = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "occupancy", usage: [.textureBinding, .copyDst], dimension: .`3D`,
                size: Extent3D(
                    width: UInt32(grid.width), height: UInt32(grid.depth), depthOrArrayLayers: UInt32(grid.height)),
                format: .r8Uint))
        let kinds = grid.data.map { material -> UInt8 in
            material == Materials.air ? 0 : Materials.isGlass(material) ? 2 : 1
        }
        kinds.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: occupancy), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(grid.width), rowsPerImage: UInt32(grid.depth)),
                writeSize: Extent3D(
                    width: UInt32(grid.width), height: UInt32(grid.depth), depthOrArrayLayers: UInt32(grid.height)))
        }
        let occupancyView = try occupancy.createView()
        let skyView = try Self.bakeSkyVisibility(device: device, occupancy: occupancyView, grid: grid)

        linearSampler = try device.createSampler(
            descriptor: SamplerDescriptor(
                addressModeU: .clampToEdge, addressModeV: .clampToEdge, addressModeW: .clampToEdge,
                magFilter: .linear, minFilter: .linear, mipmapFilter: .nearest))
        let comparisonSampler = try device.createSampler(
            descriptor: SamplerDescriptor(
                addressModeU: .clampToEdge, addressModeV: .clampToEdge, magFilter: .linear, minFilter: .linear,
                compare: .lessEqual))

        // The lamps: their positions and colors, which change as they go on
        // and off, and which of them reach each square of the ground.
        let lightTextureHeight = UInt32(max((scene.lights.count * 2 + Self.lightTextureWidth - 1) / Self.lightTextureWidth, 1))
        self.lightTextureHeight = lightTextureHeight
        lightTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamps", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(Self.lightTextureWidth), height: lightTextureHeight, depthOrArrayLayers: 1),
                format: .rgba32Float))
        let lightGrid = LightGrid(lights: scene.lights, sceneWidth: Scene.size.width, sceneDepth: Scene.size.depth)
        let cellTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamp cells", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(lightGrid.width), height: UInt32(lightGrid.depth), depthOrArrayLayers: 1),
                format: .rg32Uint))
        lightGrid.cells.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: cellTexture), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(lightGrid.width * 8), rowsPerImage: UInt32(lightGrid.depth)),
                writeSize: Extent3D(width: UInt32(lightGrid.width), height: UInt32(lightGrid.depth), depthOrArrayLayers: 1))
        }
        let indexWidth = 1024
        let indexHeight = (lightGrid.indices.count + indexWidth - 1) / indexWidth
        let paddedIndices = lightGrid.indices + [UInt32](repeating: 0, count: indexWidth * indexHeight - lightGrid.indices.count)
        let indexTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamp indices", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(indexWidth), height: UInt32(indexHeight), depthOrArrayLayers: 1),
                format: .r32Uint))
        paddedIndices.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: indexTexture), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(indexWidth * 4), rowsPerImage: UInt32(indexHeight)),
                writeSize: Extent3D(width: UInt32(indexWidth), height: UInt32(indexHeight), depthOrArrayLayers: 1))
        }

        let fragmentAndVertex: ShaderStage = [.vertex, .fragment]
        sceneLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "scene",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: fragmentAndVertex, buffer: BufferBindingLayout(type: .uniform)),
                    BindGroupLayoutEntry(binding: 1, visibility: .fragment, buffer: BufferBindingLayout(type: .uniform)),
                    BindGroupLayoutEntry(
                        binding: 2, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .unfilterableFloat, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 3, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .depth, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 4, visibility: .fragment, sampler: SamplerBindingLayout(type: .comparison)),
                    BindGroupLayoutEntry(
                        binding: 5, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .uint, viewDimension: .`3D`)),
                    BindGroupLayoutEntry(
                        binding: 6, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`3D`)),
                    BindGroupLayoutEntry(binding: 7, visibility: .fragment, sampler: SamplerBindingLayout(type: .filtering)),
                    BindGroupLayoutEntry(
                        binding: 8, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .uint, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 9, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .uint, viewDimension: .`2D`)),
                ]))
        sceneBindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "scene", layout: sceneLayout,
                entries: [
                    BindGroupEntry(binding: 0, buffer: frameBuffer),
                    BindGroupEntry(binding: 1, buffer: materialBuffer),
                    BindGroupEntry(binding: 2, textureView: try lightTexture.createView()),
                    BindGroupEntry(binding: 3, textureView: shadowView),
                    BindGroupEntry(binding: 4, sampler: comparisonSampler),
                    BindGroupEntry(binding: 5, textureView: occupancyView),
                    BindGroupEntry(binding: 6, textureView: skyView),
                    BindGroupEntry(binding: 7, sampler: linearSampler),
                    BindGroupEntry(binding: 8, textureView: try cellTexture.createView()),
                    BindGroupEntry(binding: 9, textureView: try indexTexture.createView()),
                ]))
        let shadowLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "shadow",
                entries: [BindGroupLayoutEntry(binding: 0, visibility: .vertex, buffer: BufferBindingLayout(type: .uniform))]
            ))
        shadowBindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "shadow", layout: shadowLayout, entries: [BindGroupEntry(binding: 0, buffer: frameBuffer)]))

        let vertexLayout = VertexBufferLayout(
            stepMode: .vertex, arrayStride: UInt64(VoxelMesh.wordsPerVertex * 4),
            attributes: [
                VertexAttribute(format: .float32x3, offset: 0, shaderLocation: 0),
                VertexAttribute(format: .snorm8x4, offset: 12, shaderLocation: 1),
                VertexAttribute(format: .uint8x4, offset: 16, shaderLocation: 2),
            ])
        let sceneLayoutPipeline = try device.createPipelineLayout(
            descriptor: PipelineLayoutDescriptor(label: "scene", bindGroupLayouts: [sceneLayout]))
        shadowPipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "shadow",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "shadow", bindGroupLayouts: [shadowLayout])),
                vertex: VertexState(
                    module: shadowModule, entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .vertex, arrayStride: UInt64(VoxelMesh.wordsPerVertex * 4),
                            attributes: [VertexAttribute(format: .float32x3, offset: 0, shaderLocation: 0)])
                    ]),
                primitive: PrimitiveState(topology: .triangleList, frontFace: .ccw, cullMode: .none),
                depthStencil: DepthStencilState(
                    format: Self.depthFormat, depthWriteEnabled: true, depthCompare: .less, depthBias: 4,
                    depthBiasSlopeScale: 2)))
        opaquePipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "opaque", layout: sceneLayoutPipeline,
                vertex: VertexState(module: sceneModule, entryPoint: "vertexMain", buffers: [vertexLayout]),
                primitive: PrimitiveState(topology: .triangleList, frontFace: .ccw, cullMode: .back),
                depthStencil: DepthStencilState(format: Self.depthFormat, depthWriteEnabled: true, depthCompare: .less),
                fragment: FragmentState(
                    module: sceneModule, entryPoint: "opaqueMain", targets: [ColorTargetState(format: Self.hdrFormat)])))
        let premultiplied = BlendState(
            color: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .oneMinusSrcAlpha),
            alpha: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .oneMinusSrcAlpha))
        glassPipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "glass", layout: sceneLayoutPipeline,
                vertex: VertexState(module: sceneModule, entryPoint: "vertexMain", buffers: [vertexLayout]),
                primitive: PrimitiveState(topology: .triangleList, frontFace: .ccw, cullMode: .back),
                depthStencil: DepthStencilState(format: Self.depthFormat, depthWriteEnabled: false, depthCompare: .less),
                fragment: FragmentState(
                    module: sceneModule, entryPoint: "glassMain",
                    targets: [ColorTargetState(format: Self.hdrFormat, blend: premultiplied)])))

        func postPipeline(_ entryPoint: String, format: TextureFormat, blend: BlendState? = nil) throws
            -> RenderPipeline
        {
            try device.createRenderPipeline(
                descriptor: RenderPipelineDescriptor(
                    label: entryPoint,
                    vertex: VertexState(module: postModule, entryPoint: "fullscreen"),
                    primitive: PrimitiveState(topology: .triangleList),
                    fragment: FragmentState(
                        module: postModule, entryPoint: entryPoint,
                        targets: [ColorTargetState(format: format, blend: blend)])))
        }
        downPipeline = try postPipeline("down", format: Self.hdrFormat)
        let additive = BlendState(
            color: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .one),
            alpha: BlendComponent(operation: .add, srcFactor: .one, dstFactor: .one))
        upPipeline = try postPipeline("up", format: Self.hdrFormat, blend: additive)
        compositePipeline = try postPipeline("composite", format: surfaceFormat)

        // The scene's meshes, which never change.
        let (opaque, glass) = Mesher.mesh(scene.grid)
        opaqueMesh = try Self.upload(opaque, device: device, queue: queue)
        glassMesh = try Self.upload(glass, device: device, queue: queue)
        triangleCount = opaque.triangleCount + glass.triangleCount
    }

    /// How many triangles the scene is, without the person.
    let triangleCount: Int

    private static func upload(_ mesh: VoxelMesh, device: Device, queue: Queue) throws -> Mesh? {
        guard !mesh.indices.isEmpty else { return nil }
        let vertices = try device.createBuffer(
            descriptor: BufferDescriptor(usage: [.vertex, .copyDst], size: UInt64(mesh.vertices.count * 4)))
        mesh.vertices.withUnsafeBytes { queue.writeBuffer(vertices, bufferOffset: 0, data: $0) }
        let indices = try device.createBuffer(
            descriptor: BufferDescriptor(usage: [.index, .copyDst], size: UInt64(mesh.indices.count * 4)))
        mesh.indices.withUnsafeBytes { queue.writeBuffer(indices, bufferOffset: 0, data: $0) }
        return Mesh(vertices: vertices, indices: indices, indexCount: UInt32(mesh.indices.count))
    }

    /// Bakes how much of the sky each cell of a coarse grid sees, with a
    /// compute shader.
    private static func bakeSkyVisibility(device: Device, occupancy: TextureView, grid: VoxelGrid) throws
        -> TextureView
    {
        let size = Extent3D(
            width: UInt32(grid.width / skyCellSize), height: UInt32(grid.depth / skyCellSize),
            depthOrArrayLayers: UInt32(grid.height / skyCellSize))
        let texture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "sky visibility", usage: [.storageBinding, .textureBinding], dimension: .`3D`, size: size,
                format: .rgba16Float))
        let view = try texture.createView()
        let module = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(code: Shaders.skyVisibility), label: "sky visibility"))
        let pipeline = try device.createComputePipeline(
            descriptor: ComputePipelineDescriptor(
                label: "sky visibility", compute: ComputeState(module: module, entryPoint: "main")))
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                layout: try pipeline.getBindGroupLayout(groupIndex: 0),
                entries: [BindGroupEntry(binding: 0, textureView: occupancy), BindGroupEntry(binding: 1, textureView: view)]
            ))
        let encoder = try device.createCommandEncoder()
        let pass = try encoder.beginComputePass(descriptor: ComputePassDescriptor(label: "sky visibility"))
        pass.setPipeline(pipeline)
        pass.setBindGroup(groupIndex: 0, group: bindGroup)
        pass.dispatchWorkgroups(
            x: (size.width + 3) / 4, y: (size.height + 3) / 4, z: (size.depthOrArrayLayers + 3) / 4)
        pass.end()
        device.getQueue().submit([try encoder.finish()])
        return view
    }

    /// Makes the targets for a screen `width` by `height` pixels, if they
    /// are not that size already.
    private func prepareTargets(width: UInt32, height: UInt32) throws -> Targets {
        if let targets, targets.width == width, targets.height == height {
            return targets
        }
        func texture(_ label: String, _ w: UInt32, _ h: UInt32, _ format: TextureFormat) throws -> TextureView {
            try device.createTexture(
                descriptor: TextureDescriptor(
                    label: label, usage: [.renderAttachment, .textureBinding], dimension: .`2D`,
                    size: Extent3D(width: w, height: h, depthOrArrayLayers: 1), format: format)
            ).createView()
        }
        let hdr = try texture("hdr", width, height, Self.hdrFormat)
        let depth = try texture("depth", width, height, Self.depthFormat)
        var bloom: [TextureView] = []
        var sizes: [(UInt32, UInt32)] = []
        var (w, h) = (width, height)
        for level in 0..<Self.bloomLevels {
            w = max(w / 2, 1)
            h = max(h / 2, 1)
            bloom.append(try texture("bloom \(level)", w, h, Self.hdrFormat))
            sizes.append((w, h))
        }
        func group(_ pipeline: RenderPipeline, _ entries: [BindGroupEntry]) throws -> BindGroup {
            try device.createBindGroup(
                descriptor: BindGroupDescriptor(layout: try pipeline.getBindGroupLayout(groupIndex: 0), entries: entries))
        }
        let downGroups = try (0..<Self.bloomLevels).map { level in
            try group(
                downPipeline,
                [
                    BindGroupEntry(binding: 0, textureView: level == 0 ? hdr : bloom[level - 1]),
                    BindGroupEntry(binding: 1, sampler: linearSampler),
                ])
        }
        // Each up pass reads level i and adds it into level i - 1.
        let upGroups = try (1..<Self.bloomLevels).map { level in
            try group(
                upPipeline,
                [BindGroupEntry(binding: 0, textureView: bloom[level]), BindGroupEntry(binding: 1, sampler: linearSampler)])
        }
        let compositeGroup = try group(
            compositePipeline,
            [
                BindGroupEntry(binding: 0, textureView: hdr),
                BindGroupEntry(binding: 1, sampler: linearSampler),
                BindGroupEntry(binding: 2, textureView: bloom[0]),
                BindGroupEntry(binding: 3, buffer: settingsBuffer),
            ])
        let made = Targets(
            width: width, height: height, hdr: hdr, depth: depth, bloom: bloom, bloomSizes: sizes,
            downGroups: downGroups, upGroups: upGroups, compositeGroup: compositeGroup)
        targets = made
        return made
    }

    /// Records a frame into `surface`, then `drawOverlay` over it.
    func draw(
        frame: FrameUniforms, materials: [Vector4<Float>], lights: [Vector4<Float>], character: VoxelMesh,
        bloomStrength: Float, into surface: TextureView, width: UInt32, height: UInt32, encoder: CommandEncoder,
        drawOverlay: (RenderPassEncoder) throws -> Void
    ) throws {
        let targets = try prepareTargets(width: width, height: height)
        withUnsafeBytes(of: frame) { queue.writeBuffer(frameBuffer, bufferOffset: 0, data: $0) }
        materials.withUnsafeBytes { queue.writeBuffer(materialBuffer, bufferOffset: 0, data: $0) }
        let lightTexels = Self.lightTextureWidth * Int(lightTextureHeight)
        let paddedLights = lights + [Vector4<Float>](repeating: .zero, count: lightTexels - lights.count)
        paddedLights.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: lightTexture), data: data,
                dataLayout: TexelCopyBufferLayout(
                    bytesPerRow: UInt32(Self.lightTextureWidth * 16), rowsPerImage: lightTextureHeight),
                writeSize: Extent3D(
                    width: UInt32(Self.lightTextureWidth), height: lightTextureHeight, depthOrArrayLayers: 1))
        }
        let gammaEncodes: Float =
            [.rgba8UnormSrgb, .bgra8UnormSrgb].contains(surfaceFormat) ? 0 : 1
        let settings: [Float] = [frame.params.y, bloomStrength, gammaEncodes, 0]
        settings.withUnsafeBytes { queue.writeBuffer(settingsBuffer, bufferOffset: 0, data: $0) }
        try updateCharacter(character)

        func drawMesh(_ mesh: Mesh?, in pass: RenderPassEncoder) {
            guard let mesh else { return }
            pass.setVertexBuffer(slot: 0, buffer: mesh.vertices, offset: 0, size: wholeSize)
            pass.setIndexBuffer(buffer: mesh.indices, format: .uint32, offset: 0, size: UInt64(mesh.indexCount) * 4)
            pass.drawIndexed(indexCount: mesh.indexCount, instanceCount: 1, firstIndex: 0, baseVertex: 0, firstInstance: 0)
        }

        // Depth from the sun.
        let shadowPass = try encoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                label: "shadow", colorAttachments: [],
                depthStencilAttachment: RenderPassDepthStencilAttachment(
                    view: shadowView, depthLoadOp: .clear, depthStoreOp: .store, depthClearValue: 1)))
        shadowPass.setPipeline(shadowPipeline)
        shadowPass.setBindGroup(groupIndex: 0, group: shadowBindGroup)
        drawMesh(opaqueMesh, in: shadowPass)
        drawMesh(characterMesh, in: shadowPass)
        shadowPass.end()

        // The scene in light, then glass over it.
        let horizon = frame.horizonColor
        let scenePass = try encoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                label: "scene",
                colorAttachments: [
                    RenderPassColorAttachment(
                        view: targets.hdr, loadOp: .clear, storeOp: .store,
                        clearValue: Color(r: Double(horizon.x), g: Double(horizon.y), b: Double(horizon.z), a: 1))
                ],
                depthStencilAttachment: RenderPassDepthStencilAttachment(
                    view: targets.depth, depthLoadOp: .clear, depthStoreOp: .discard, depthClearValue: 1)))
        scenePass.setBindGroup(groupIndex: 0, group: sceneBindGroup)
        scenePass.setPipeline(opaquePipeline)
        drawMesh(opaqueMesh, in: scenePass)
        drawMesh(characterMesh, in: scenePass)
        scenePass.setPipeline(glassPipeline)
        drawMesh(glassMesh, in: scenePass)
        scenePass.end()

        // Bloom: halve down the levels, then add each back into the next
        // larger.
        func fullscreenPass(
            _ view: TextureView, load: LoadOp, pipeline: RenderPipeline, group: BindGroup, label: String
        ) throws {
            let pass = try encoder.beginRenderPass(
                descriptor: RenderPassDescriptor(
                    label: label,
                    colorAttachments: [
                        RenderPassColorAttachment(
                            view: view, loadOp: load, storeOp: .store, clearValue: Color(r: 0, g: 0, b: 0, a: 1))
                    ]))
            pass.setPipeline(pipeline)
            pass.setBindGroup(groupIndex: 0, group: group)
            pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
            pass.end()
        }
        for level in 0..<Self.bloomLevels {
            try fullscreenPass(
                targets.bloom[level], load: .clear, pipeline: downPipeline, group: targets.downGroups[level],
                label: "bloom down")
        }
        for level in stride(from: Self.bloomLevels - 1, to: 0, by: -1) {
            try fullscreenPass(
                targets.bloom[level - 1], load: .load, pipeline: upPipeline, group: targets.upGroups[level - 1],
                label: "bloom up")
        }

        // To the screen, with the overlay on top.
        let pass = try encoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                label: "composite",
                colorAttachments: [
                    RenderPassColorAttachment(
                        view: surface, loadOp: .clear, storeOp: .store, clearValue: Color(r: 0, g: 0, b: 0, a: 1))
                ]))
        pass.setPipeline(compositePipeline)
        pass.setBindGroup(groupIndex: 0, group: targets.compositeGroup)
        pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
        try drawOverlay(pass)
        pass.end()
    }

    /// Writes the person's triangles, which keep their count from frame to
    /// frame.
    private func updateCharacter(_ mesh: VoxelMesh) throws {
        guard !mesh.indices.isEmpty else { return }
        if characterMesh == nil {
            characterMesh = try Self.upload(mesh, device: device, queue: queue)
            return
        }
        mesh.vertices.withUnsafeBytes { queue.writeBuffer(characterMesh!.vertices, bufferOffset: 0, data: $0) }
    }
}
