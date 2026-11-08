import Dawn
import GameToolkit
import MainLoop
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
    /// The voxels the occupancy texture holds: the lowest x and z, and how
    /// many along each. The renderer fills this in.
    var window: Vector4<Float> = .zero
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
    /// How many chunks across the occupancy texture holds around the camera:
    /// a power of two, for the shaders' wrapping around it to be a mask.
    static let windowChunks = 8
    static var windowVoxels: Int { windowChunks * SceneChunk.size }
    /// How long a frame may spend moving the occupancy window.
    static let windowBudget = Duration.milliseconds(2)
    /// How many voxels of the grid a cell of the sky's grid covers each way.
    static let skyCellSize = 4
    /// How many chunks across the texture the sky is baked from holds: three
    /// are needed around the chunk being baked, and a ring is a power of two.
    static let bakeWindowChunks = 4
    /// How long a frame may spend making chunks.
    static let streamingBudget = Duration.milliseconds(4)
    /// How long to work between showing frames while there is nothing to see.
    static let loadingBudget = Duration.milliseconds(12)
    /// How many chunks around the focus are made before the first frame.
    static let startingRadius = 2
    /// How much room the lamps' grid has for its lists.
    static let lampIndexWidth = 1024
    static let lampIndexRows = 128

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
    private let cellTexture: Texture
    private let indexTexture: Texture
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
    private struct Chunk {
        var minimum: Vector3<Float>
        var maximum: Vector3<Float>
        var opaque: Mesh?
        var glass: Mesh?
    }
    private var chunks: [Chunk] = []
    private let world: World
    private var voxels: SparseVoxels { world.voxels }
    private let occupancyTexture: Texture
    private let skyTexture: Texture
    private let bakeOccupancyTexture: Texture
    private let bakePipeline: ComputePipeline
    private let bakeLayout: BindGroupLayout
    private let bakeOccupancyView: TextureView
    private let bakeOutputView: TextureView
    /// Which chunk each slot of the baking texture holds.
    private var bakeSlots = [SIMD2<Int>?](repeating: nil, count: Renderer.bakeWindowChunks * Renderer.bakeWindowChunks)

    /// The piece of making a chunk that is under way.
    private enum Job {
        case generating(SIMD2<Int>, Town)
        case meshing(SIMD2<Int>, ChunkMeshing)
        /// Loading the chunks around one into the baking texture, the last
        /// first, from a slice of the last, and then baking.
        case baking(SIMD2<Int>, pending: [SIMD2<Int>], nextSlice: Int)
    }
    private var job: Job?
    private var isMeshed: [Bool]
    private var isBaked: [Bool]
    /// The chunks of the world, nearest the focus first, and that focus.
    private var chunkOrder: [SIMD2<Int>] = []
    private var orderCenter: SIMD2<Int>?
    private var lampsChanged = false
    /// Whether every chunk has been made.
    private(set) var isComplete = false
    /// A move of the window that is under way: the chunks still to write,
    /// and the slice next to write of the last of them.
    private struct WindowMove {
        var center: SIMD2<Int>
        var pending: [SIMD2<Int>]
        var nextSlice = 0
    }
    private var windowCenter: SIMD2<Int>?
    private var windowMove: WindowMove?
    /// Which chunk each slot of the occupancy texture holds.
    private var loadedChunks = [SIMD2<Int>?](repeating: nil, count: Renderer.windowChunks * Renderer.windowChunks)
    /// How many chunks and triangles the last frame drew from the camera.
    private(set) var drawnChunks = 0
    private(set) var drawnTriangles = 0
    /// How many triangles the last frame drew from the sun.
    private(set) var shadowTriangles = 0
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
        let voxels = scene.voxels
        world = scene.world
        isMeshed = [Bool](repeating: false, count: scene.world.chunksX * scene.world.chunksZ)
        isBaked = isMeshed
        occupancyTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "occupancy", usage: [.textureBinding, .copyDst], dimension: .`3D`,
                size: Extent3D(
                    width: UInt32(Self.windowVoxels), height: UInt32(Self.windowVoxels),
                    depthOrArrayLayers: UInt32(voxels.height)),
                format: .r8Uint))
        let occupancyView = try occupancyTexture.createView()
        skyTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "sky visibility", usage: [.storageBinding, .textureBinding], dimension: .`3D`,
                size: Extent3D(
                    width: UInt32(voxels.width / Self.skyCellSize), height: UInt32(voxels.depth / Self.skyCellSize),
                    depthOrArrayLayers: UInt32(voxels.height / Self.skyCellSize)),
                format: .rgba16Float))
        let skyView = try skyTexture.createView()
        bakeOutputView = skyView
        bakeOccupancyTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "baking occupancy", usage: [.textureBinding, .copyDst], dimension: .`3D`,
                size: Extent3D(
                    width: UInt32(Self.bakeWindowChunks * SceneChunk.size),
                    height: UInt32(Self.bakeWindowChunks * SceneChunk.size), depthOrArrayLayers: UInt32(voxels.height)),
                format: .r8Uint))
        bakeOccupancyView = try bakeOccupancyTexture.createView()
        let bakeModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(code: Shaders.skyVisibility), label: "sky visibility"))
        bakePipeline = try device.createComputePipeline(
            descriptor: ComputePipelineDescriptor(
                label: "sky visibility", compute: ComputeState(module: bakeModule, entryPoint: "main")))
        bakeLayout = try bakePipeline.getBindGroupLayout(groupIndex: 0)

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
        let lampRoom = max(scene.lights.count, World.maxLamps)
        let lightTextureHeight = UInt32((lampRoom * 2 + Self.lightTextureWidth - 1) / Self.lightTextureWidth)
        self.lightTextureHeight = lightTextureHeight
        lightTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamps", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(Self.lightTextureWidth), height: lightTextureHeight, depthOrArrayLayers: 1),
                format: .rgba32Float))
        let (gridWidth, gridDepth) = LightGrid.dimensions(sceneWidth: scene.width, sceneDepth: scene.depth)
        let cellTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamp cells", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(width: UInt32(gridWidth), height: UInt32(gridDepth), depthOrArrayLayers: 1),
                format: .rg32Uint))
        self.cellTexture = cellTexture
        let indexTexture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "lamp indices", usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(
                    width: UInt32(Self.lampIndexWidth), height: UInt32(Self.lampIndexRows), depthOrArrayLayers: 1),
                format: .r32Uint))
        self.indexTexture = indexTexture

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

        writeLampGrid()
    }

    /// How many triangles are made so far, without the person.
    private(set) var triangleCount = 0

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

    private static func modulo(_ value: Int) -> Int {
        ((value % windowChunks) + windowChunks) % windowChunks
    }

    /// The chunks of the window around a chunk that are not in the texture.
    private func missingChunks(centerX: Int, centerZ: Int) -> [SIMD2<Int>] {
        let wide = Self.windowChunks
        let half = wide / 2
        var missing: [SIMD2<Int>] = []
        for chunkZ in (centerZ - half)..<(centerZ - half + wide) {
            for chunkX in (centerX - half)..<(centerX - half + wide) {
                let chunk = SIMD2(chunkX, chunkZ)
                if loadedChunks[Self.modulo(chunkZ) * wide + Self.modulo(chunkX)] != chunk {
                    missing.append(chunk)
                }
            }
        }
        return missing
    }

    /// Writes one slice of a chunk's occupancy into its slot of the texture.
    private func uploadSlice(_ slice: Int, of chunk: SIMD2<Int>) {
        uploadSlice(slice, of: chunk, into: occupancyTexture, chunksAcross: Self.windowChunks)
    }

    private func uploadSlice(_ slice: Int, of chunk: SIMD2<Int>, into texture: Texture, chunksAcross: Int) {
        let size = SceneChunk.size
        func wrapped(_ value: Int) -> Int { ((value % chunksAcross) + chunksAcross) % chunksAcross }
        let occupancy = voxels.occupancySlice(
            x: (chunk.x * size)..<((chunk.x + 1) * size), z: (chunk.y * size)..<((chunk.y + 1) * size), slice: slice)
        let height = SparseVoxels.sliceHeight
        occupancy.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(
                    texture: texture,
                    origin: Origin3D(
                        x: UInt32(wrapped(chunk.x) * size), y: UInt32(wrapped(chunk.y) * size),
                        z: UInt32(slice * height))),
                data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(size), rowsPerImage: UInt32(size)),
                writeSize: Extent3D(width: UInt32(size), height: UInt32(size), depthOrArrayLayers: UInt32(height)))
        }
    }

    private func slot(of chunk: SIMD2<Int>) -> Int {
        Self.modulo(chunk.y) * Self.windowChunks + Self.modulo(chunk.x)
    }

    /// The voxels of the window around a chunk: the lowest x and z, and the
    /// ends past the highest.
    private static func windowBounds(_ center: SIMD2<Int>) -> (low: SIMD2<Int>, high: SIMD2<Int>) {
        let low = (center &- SIMD2(repeating: windowChunks / 2)) &* SIMD2(repeating: SceneChunk.size)
        return (low, low &+ SIMD2(repeating: windowVoxels))
    }

    private static func windowUniform(low: SIMD2<Int>, high: SIMD2<Int>) -> Vector4<Float> {
        Vector4(Float(low.x), Float(low.y), Float(high.x - low.x), Float(high.y - low.y))
    }

    /// Finishes with the window around a chunk, once all of it is loaded.
    private func settleWindow(at center: SIMD2<Int>) -> Vector4<Float> {
        windowCenter = center
        windowMove = nil
        let bounds = Self.windowBounds(center)
        return Self.windowUniform(low: bounds.low, high: bounds.high)
    }

    /// Holds the chunks around one in the occupancy texture at once, giving
    /// way to the browser in between, for when there is nothing to show yet.
    private func moveWindow(centerX: Int, centerZ: Int) async -> Vector4<Float> {
        var breather = Breather()
        for chunk in missingChunks(centerX: centerX, centerZ: centerZ) {
            loadedChunks[slot(of: chunk)] = nil
            for slice in 0..<voxels.sliceCount {
                uploadSlice(slice, of: chunk)
                await breather.breathe()
            }
            loadedChunks[slot(of: chunk)] = chunk
        }
        return settleWindow(at: SIMD2(centerX, centerZ))
    }

    /// Follows the camera, spending only a little of each frame: the window
    /// moves a slice of a chunk at a time. Until it is done, the window in
    /// use is only what the old and new windows share, as the chunks that
    /// leave give up their slots to those that come.
    private func followCamera(centerX: Int, centerZ: Int) -> Vector4<Float> {
        let center = SIMD2(centerX, centerZ)
        guard let current = windowCenter else {
            return Self.windowUniform(low: SIMD2(repeating: 0), high: SIMD2(repeating: 0))
        }
        if windowMove == nil {
            let missing = missingChunks(centerX: centerX, centerZ: centerZ)
            guard !missing.isEmpty else {
                let bounds = Self.windowBounds(current)
                return Self.windowUniform(low: bounds.low, high: bounds.high)
            }
            windowMove = WindowMove(center: center, pending: missing)
        }
        var bounds = Self.windowBounds(current)
        guard var move = windowMove else {
            return Self.windowUniform(low: bounds.low, high: bounds.high)
        }
        let clock = ContinuousClock()
        let start = clock.now
        repeat {
            guard let chunk = move.pending.last else { break }
            if move.nextSlice == 0 {
                loadedChunks[slot(of: chunk)] = nil
            }
            uploadSlice(move.nextSlice, of: chunk)
            move.nextSlice += 1
            if move.nextSlice == voxels.sliceCount {
                loadedChunks[slot(of: chunk)] = chunk
                move.pending.removeLast()
                move.nextSlice = 0
            }
        } while !move.pending.isEmpty && clock.now - start < Self.windowBudget
        if move.pending.isEmpty {
            return settleWindow(at: move.center)
        }
        windowMove = move
        let target = Self.windowBounds(move.center)
        bounds.low = pointwiseMax(bounds.low, target.low)
        bounds.high = pointwiseMin(bounds.high, target.high)
        // Nothing shared: nothing is known to be ready yet.
        if bounds.low.x >= bounds.high.x || bounds.low.y >= bounds.high.y {
            return Self.windowUniform(low: SIMD2(repeating: 0), high: SIMD2(repeating: 0))
        }
        return Self.windowUniform(low: bounds.low, high: bounds.high)
    }

    // MARK: Making chunks

    /// Writes which lamps reach each square of the ground.
    private func writeLampGrid() {
        let grid = LightGrid(lights: world.lights, sceneWidth: Float(voxels.width) / Float(voxelsPerMeter), sceneDepth: Float(voxels.depth) / Float(voxelsPerMeter))
        grid.cells.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: cellTexture), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(grid.width * 8), rowsPerImage: UInt32(grid.depth)),
                writeSize: Extent3D(width: UInt32(grid.width), height: UInt32(grid.depth), depthOrArrayLayers: 1))
        }
        let width = Self.lampIndexWidth
        let rows = min((grid.indices.count + width - 1) / width, Self.lampIndexRows)
        var indices = Array(grid.indices.prefix(width * rows))
        indices += [UInt32](repeating: 0, count: width * rows - indices.count)
        indices.withUnsafeBytes { data in
            queue.writeTexture(
                destination: TexelCopyTextureInfo(texture: indexTexture), data: data,
                dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(width * 4), rowsPerImage: UInt32(rows)),
                writeSize: Extent3D(width: UInt32(width), height: UInt32(rows), depthOrArrayLayers: 1))
        }
    }

    /// The chunk the voxels of a point in meters belong to.
    private static func chunk(at focus: Vector3<Float>) -> SIMD2<Int> {
        let meters = Float(SceneChunk.size) / Float(voxelsPerMeter)
        return SIMD2(Int((focus.x / meters).rounded(.down)), Int((focus.z / meters).rounded(.down)))
    }

    /// What to make next for the chunks nearest `center`, within `radius`
    /// chunks of it: a chunk is meshed and baked from its voxels and those
    /// around it, so those come first.
    private func nextJob(center: SIMD2<Int>, radius: Int) -> Job? {
        if orderCenter != center {
            orderCenter = center
            chunkOrder = (0..<world.chunksZ).flatMap { z in (0..<world.chunksX).map { SIMD2($0, z) } }
            func distance(_ chunk: SIMD2<Int>) -> Int {
                let offset = chunk &- center
                return offset.x * offset.x + offset.y * offset.y
            }
            chunkOrder.sort { distance($0) < distance($1) }
        }
        for chunk in chunkOrder {
            guard let index = world.index(of: chunk), !isMeshed[index] || !isBaked[index] else { continue }
            if abs(chunk.x - center.x) > radius || abs(chunk.y - center.y) > radius { continue }
            for z in -1...1 {
                for x in -1...1 where !world.isSettled(chunk &+ SIMD2(x, z)) {
                    let neighbor = chunk &+ SIMD2(x, z)
                    return .generating(neighbor, world.startGenerating(neighbor))
                }
            }
            if !isMeshed[index] {
                let size = SceneChunk.size
                return .meshing(chunk, ChunkMeshing(x: chunk.x * size, z: chunk.y * size, voxels: voxels))
            }
            var pending: [SIMD2<Int>] = []
            for z in -1...1 {
                for x in -1...1 {
                    let around = chunk &+ SIMD2(x, z)
                    if bakeSlots[bakeSlot(of: around)] != around { pending.append(around) }
                }
            }
            return .baking(chunk, pending: pending, nextSlice: 0)
        }
        return nil
    }

    private func bakeSlot(of chunk: SIMD2<Int>) -> Int {
        let wide = Self.bakeWindowChunks
        return ((chunk.y % wide + wide) % wide) * wide + (chunk.x % wide + wide) % wide
    }

    /// Does one small piece of the job under way.
    private func runJobStep(_ current: Job) throws -> Job? {
        switch current {
        case .generating(let chunk, var town):
            if town.buildNextLot() {
                return .generating(chunk, town)
            }
            if world.finishGenerating(chunk, town: town) {
                lampsChanged = true
            }
            invalidateWindow(chunk)
            return nil
        case .meshing(let chunk, var meshing):
            if meshing.step() {
                return .meshing(chunk, meshing)
            }
            if let made = meshing.finished() {
                chunks.append(
                    Chunk(
                        minimum: made.minimum, maximum: made.maximum,
                        opaque: try Self.upload(made.opaque, device: device, queue: queue),
                        glass: try Self.upload(made.glass, device: device, queue: queue)))
                triangleCount += made.opaque.triangleCount + made.glass.triangleCount
            }
            if let index = world.index(of: chunk) { isMeshed[index] = true }
            return nil
        case .baking(let chunk, var pending, var nextSlice):
            guard let loading = pending.last else {
                try bake(chunk)
                if let index = world.index(of: chunk) { isBaked[index] = true }
                return nil
            }
            if nextSlice == 0 { bakeSlots[bakeSlot(of: loading)] = nil }
            uploadSlice(nextSlice, of: loading, into: bakeOccupancyTexture, chunksAcross: Self.bakeWindowChunks)
            nextSlice += 1
            if nextSlice == voxels.sliceCount {
                bakeSlots[bakeSlot(of: loading)] = loading
                pending.removeLast()
                nextSlice = 0
            }
            return .baking(chunk, pending: pending, nextSlice: nextSlice)
        }
    }

    /// Makes the occupancy window load a chunk again, now that it has changed.
    private func invalidateWindow(_ chunk: SIMD2<Int>) {
        if loadedChunks[slot(of: chunk)] == chunk {
            loadedChunks[slot(of: chunk)] = nil
        }
        if windowMove?.pending.last == chunk {
            windowMove?.nextSlice = 0
        }
    }

    /// Bakes how much of the sky each cell of a chunk sees, with a compute
    /// shader. Rays look a chunk to the side, for the same reach everywhere.
    private func bake(_ chunk: SIMD2<Int>) throws {
        let size = SceneChunk.size
        let cellsPerChunk = size / Self.skyCellSize
        let parameters: [Int32] = [
            Int32((chunk.x - 1) * size), Int32((chunk.y - 1) * size), Int32(Self.bakeWindowChunks * size), Int32(size),
            Int32(chunk.x * cellsPerChunk), Int32(chunk.y * cellsPerChunk), Int32(cellsPerChunk), Int32(cellsPerChunk),
            Int32(voxels.width), Int32(voxels.height), Int32(voxels.depth), Int32(Self.skyCellSize),
        ]
        let uniform = try device.createBuffer(
            descriptor: BufferDescriptor(usage: [.uniform, .copyDst], size: UInt64(parameters.count * 4)))
        parameters.withUnsafeBytes { queue.writeBuffer(uniform, bufferOffset: 0, data: $0) }
        let bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                layout: bakeLayout,
                entries: [
                    BindGroupEntry(binding: 0, textureView: bakeOccupancyView),
                    BindGroupEntry(binding: 1, textureView: bakeOutputView),
                    BindGroupEntry(binding: 2, buffer: uniform),
                ]))
        let encoder = try device.createCommandEncoder()
        let pass = try encoder.beginComputePass(descriptor: ComputePassDescriptor(label: "sky visibility"))
        pass.setPipeline(bakePipeline)
        pass.setBindGroup(groupIndex: 0, group: bindGroup)
        pass.dispatchWorkgroups(
            x: UInt32((cellsPerChunk + 3) / 4), y: UInt32((cellsPerChunk + 3) / 4),
            z: UInt32((voxels.height / Self.skyCellSize + 3) / 4))
        pass.end()
        queue.submit([try encoder.finish()])
    }

    /// Works at the chunks nearest `center` for about `budget`. Says whether
    /// nothing was left to do within `radius`.
    private func makeChunks(center: SIMD2<Int>, radius: Int, budget: Duration) throws -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        var isDone = false
        repeat {
            if job == nil {
                job = nextJob(center: center, radius: radius)
            }
            guard let current = job else {
                isDone = true
                break
            }
            // Taken out while it changes, for its arrays not to be copied.
            job = nil
            job = try runJobStep(current)
        } while clock.now - start < budget
        if lampsChanged {
            lampsChanged = false
            writeLampGrid()
        }
        return isDone
    }

    /// Makes the chunks around a point, or all of them, before anything is
    /// shown, giving way to the browser in between, and holds what is around
    /// the point in the occupancy window.
    func load(around focus: Vector3<Float>, everything: Bool) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let center = Self.chunk(at: focus)
        let radius = everything ? Int.max / 2 : Self.startingRadius
        var breather = Breather()
        while !(try makeChunks(center: center, radius: radius, budget: Self.loadingBudget)) {
            await breather.breathe()
        }
        _ = await moveWindow(centerX: center.x, centerZ: center.y)
        isComplete = everything
        print(
            "Loaded \(chunks.count) chunks of \(world.chunksX * world.chunksZ) in \(clock.now - start): \(triangleCount) triangles, \(world.lights.count) lamps, \(voxels.denseBytes / 1_000_000) MB of voxels."
        )
    }

    // MARK: Measuring

    /// Times, for the chunks around a point, what making a chunk asks of the
    /// GPU, and prints it. Each piece is repeated and the wait for the GPU
    /// divided among the repeats, as in a browser the wait can only be seen
    /// to end at a frame.
    func measureGPU(around focus: Vector3<Float>, instance: Instance) async throws {
        while let current = job {
            job = nil
            job = try runJobStep(current)
        }
        let fence = try device.createBuffer(descriptor: BufferDescriptor(usage: .copySrc, size: 4))
        let fenceCopy = try device.createBuffer(descriptor: BufferDescriptor(usage: [.mapRead, .copyDst], size: 4))
        func finishGPU() async throws {
            let encoder = try device.createCommandEncoder()
            encoder.copyBufferToBuffer(source: fence, destination: fenceCopy, size: 4)
            queue.submit([try encoder.finish()])
            let mapped = Flag()
            Task {
                do {
                    try await fenceCopy.mapAsync(mode: .read)
                } catch {
                    mapped.error = error
                }
                mapped.isSet = true
            }
            while !mapped.isSet {
                instance.processEvents()
                #if os(Emscripten)
                    await nextFrame()
                #else
                    await Task.yield()
                #endif
            }
            if let error = mapped.error { throw error }
            fenceCopy.unmap()
        }
        func milliseconds(_ duration: Duration) -> Double {
            let (seconds, attoseconds) = duration.components
            return Double(seconds) * 1000 + Double(attoseconds) / 1e15
        }
        struct Samples {
            var cpu: [Double] = []
            var total: [Double] = []
        }
        let clock = ContinuousClock()
        /// Runs `piece` some times over, then waits for the GPU.
        func timed(_ repeats: Int, into samples: inout Samples, _ piece: () throws -> Void) async throws {
            try await finishGPU()
            let start = clock.now
            for _ in 0..<repeats {
                try piece()
            }
            let issued = clock.now
            try await finishGPU()
            samples.cpu.append(milliseconds(issued - start) / Double(repeats))
            samples.total.append(milliseconds(clock.now - start) / Double(repeats))
        }

        var bakes = Samples()
        var groundSlices = Samples()
        var airSlices = Samples()
        var meshes = Samples()
        var meshBytes: [Int] = []
        let center = Self.chunk(at: focus)
        let size = SceneChunk.size
        for z in -2...2 {
            for x in -2...2 {
                let chunk = center &+ SIMD2(x, z)
                guard let index = world.index(of: chunk), isMeshed[index] else { continue }
                for aroundZ in -1...1 {
                    for aroundX in -1...1 {
                        let around = chunk &+ SIMD2(aroundX, aroundZ)
                        for slice in 0..<voxels.sliceCount {
                            uploadSlice(slice, of: around, into: bakeOccupancyTexture, chunksAcross: Self.bakeWindowChunks)
                        }
                    }
                }
                try await timed(16, into: &bakes) { try bake(chunk) }
                try await timed(16, into: &groundSlices) {
                    uploadSlice(0, of: chunk, into: bakeOccupancyTexture, chunksAcross: Self.bakeWindowChunks)
                }
                try await timed(16, into: &airSlices) {
                    uploadSlice(voxels.sliceCount - 1, of: chunk, into: bakeOccupancyTexture, chunksAcross: Self.bakeWindowChunks)
                }
                var meshing = ChunkMeshing(x: chunk.x * size, z: chunk.y * size, voxels: voxels)
                while meshing.step() {}
                if let made = meshing.finished() {
                    meshBytes.append((made.opaque.vertices.count + made.opaque.indices.count + made.glass.vertices.count + made.glass.indices.count) * 4)
                    var kept: [Mesh?] = []
                    try await timed(8, into: &meshes) {
                        kept.append(try Self.upload(made.opaque, device: device, queue: queue))
                        kept.append(try Self.upload(made.glass, device: device, queue: queue))
                    }
                    withExtendedLifetime(kept) {}
                }
                await nextFrame()
            }
        }
        // What the texture holds is no longer known.
        bakeSlots = [SIMD2<Int>?](repeating: nil, count: bakeSlots.count)

        func report(_ name: String, _ samples: Samples) {
            func text(_ value: Double) -> String { "\(Double(Int(value * 100)) / 100)" }
            func line(_ values: [Double]) -> String {
                let sorted = values.sorted()
                guard let last = sorted.last else { return "none" }
                return "median \(text(sorted[sorted.count / 2])), max \(text(last))"
            }
            print("  \(name): issuing \(line(samples.cpu)) ms; through the GPU \(line(samples.total)) ms")
        }
        print("gpu cost of making a chunk, \(bakes.total.count) chunks:")
        report("sky bake", bakes)
        report("voxel slice, ground (512 KB)", groundSlices)
        report("voxel slice, air (512 KB)", airSlices)
        report("mesh buffers", meshes)
        if !meshBytes.isEmpty {
            print("  mesh size: \(meshBytes.reduce(0, +) / meshBytes.count / 1000) KB on average, \((meshBytes.max() ?? 0) / 1000) KB at most")
        }
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
        frame baseFrame: FrameUniforms, focus: Vector3<Float>, materials: [Vector4<Float>], lights: [Vector4<Float>], character: VoxelMesh,
        bloomStrength: Float, into surface: TextureView, width: UInt32, height: UInt32, encoder: CommandEncoder,
        drawOverlay: (RenderPassEncoder) throws -> Void
    ) throws {
        let targets = try prepareTargets(width: width, height: height)
        var frame = baseFrame
        let center = Self.chunk(at: focus)
        if !isComplete, try makeChunks(center: center, radius: Int.max / 2, budget: Self.streamingBudget) {
            isComplete = true
            print("Made every chunk: \(triangleCount) triangles, \(world.lights.count) lamps.")
        }
        frame.window = followCamera(centerX: center.x, centerZ: center.y)
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

        func isInView(_ chunk: Chunk, _ viewProjection: Matrix4x4<Float>) -> Bool {
            var outside = (left: true, right: true, bottom: true, top: true)
            for corner in 0..<8 {
                let point = Vector4<Float>(
                    corner & 1 == 0 ? chunk.minimum.x : chunk.maximum.x, corner & 2 == 0 ? chunk.minimum.y : chunk.maximum.y,
                    corner & 4 == 0 ? chunk.minimum.z : chunk.maximum.z, 1)
                let clip = viewProjection * point
                outside.left = outside.left && clip.x < -clip.w
                outside.right = outside.right && clip.x > clip.w
                outside.bottom = outside.bottom && clip.y < -clip.w
                outside.top = outside.top && clip.y > clip.w
            }
            return !(outside.left || outside.right || outside.bottom || outside.top)
        }

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
        shadowTriangles = 0
        for chunk in chunks where isInView(chunk, frame.sunViewProjection) {
            drawMesh(chunk.opaque, in: shadowPass)
            shadowTriangles += Int(chunk.opaque?.indexCount ?? 0) / 3
        }
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
        let visible = chunks.filter { isInView($0, frame.viewProjection) }
        drawnChunks = visible.count
        drawnTriangles = visible.reduce(0) { $0 + Int(($1.opaque?.indexCount ?? 0) + ($1.glass?.indexCount ?? 0)) / 3 }
        for chunk in visible {
            drawMesh(chunk.opaque, in: scenePass)
        }
        drawMesh(characterMesh, in: scenePass)
        scenePass.setPipeline(glassPipeline)
        for chunk in visible {
            drawMesh(chunk.glass, in: scenePass)
        }
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
