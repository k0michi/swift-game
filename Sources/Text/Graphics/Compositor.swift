import Dawn

// How views draw: they record items of kinds of drawing into a display list,
// and the compositor, which knows no kind, runs the list. It groups adjacent
// items of a kind under one clip, has each group prepared before any pass, and
// encodes the groups in order, ending the pass before a kind that reads what
// has been drawn behind it. Nothing it draws is built in: text and rectangles
// are kinds like any other.

/// What a kind of drawing, or anything else, keeps from frame to frame and
/// shares among all that use it: pipelines, an atlas, caches. There is one of
/// each type: put in with `register(_:)` when it needs what only the app has,
/// such as a font, or made the first time it is asked for otherwise.
@MainActor
protocol GraphicsResource: AnyObject {
    func beginFrame()
    func endFrame()
}

/// A resource the compositor can make itself.
@MainActor
protocol MadeGraphicsResource: GraphicsResource {
    init(compositor: Compositor) throws
}

extension GraphicsResource {
    func beginFrame() {}
    func endFrame() {}
}

/// A kind of drawing: what it is given for each thing it draws, how it gets a
/// group of them ready, and how it encodes them.
@MainActor
protocol DrawingKind {
    associatedtype Resource: GraphicsResource
    associatedtype Item
    associatedtype Prepared

    /// Whether it reads what has been drawn behind it, before which the pass
    /// ends. Its items are not grouped.
    static var readsBackdrop: Bool { get }

    /// Gets a group of items ready, before any pass: uploads and the like.
    static func prepare(_ items: [Item], resource: Resource, in context: PrepareContext) throws -> Prepared

    /// For a kind that reads its backdrop: its work with what has been drawn,
    /// between the pass before it and the one it is encoded in.
    static func encodeOffscreen(_ prepared: Prepared, resource: Resource, in context: OffscreenContext) throws

    /// Encodes the group into the pass.
    static func encode(_ prepared: Prepared, resource: Resource, in context: EncodeContext) throws
}

extension DrawingKind {
    static var readsBackdrop: Bool { false }

    static func encodeOffscreen(_ prepared: Prepared, resource: Resource, in context: OffscreenContext) throws {}
}

/// A rectangle in points or pixels.
struct Rect: Equatable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float

    func scaled(by scale: Float) -> Rect {
        Rect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    func intersection(_ other: Rect) -> Rect {
        let left = max(x, other.x)
        let top = max(y, other.y)
        let right = min(x + width, other.x + other.width)
        let bottom = min(y + height, other.y + other.height)
        return Rect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }
}

struct PrepareContext {
    let device: Device
    let queue: Queue
    /// The size of what is drawn into, in pixels.
    let width: Float
    let height: Float
}

struct OffscreenContext {
    let device: Device
    let encoder: CommandEncoder
    /// What has been drawn, to sample, and its size in pixels.
    let backdrop: TextureView
    let width: Float
    let height: Float
}

struct EncodeContext {
    let device: Device
    let pass: RenderPassEncoder
    let width: Float
    let height: Float
}

@MainActor
final class Compositor {
    let device: Device
    /// The format of what is drawn into, the surface's.
    let format: TextureFormat
    /// Pixels to the point.
    var scale: Float
    /// When the frame is, in seconds.
    var time: Double = 0

    private var resources: [ObjectIdentifier: GraphicsResource] = [:]
    private var entries: [Entry] = []
    private var kinds: [ObjectIdentifier: KindFunctions] = [:]
    private var clipStack: [Rect] = []
    // What the frame is drawn into, before it is copied onto the surface, for
    // a kind that reads its backdrop to sample.
    private var target: (texture: Texture, view: TextureView, width: UInt32, height: UInt32)?

    init(device: Device, format: TextureFormat, scale: Float) {
        self.device = device
        self.format = format
        self.scale = scale
    }

    /// The resource of `type`: the one registered, or one made the first time.
    func resource<R: GraphicsResource>(_ type: R.Type) throws -> R {
        if let resource = resources[ObjectIdentifier(type)] {
            return resource as! R
        }
        guard let made = type as? any MadeGraphicsResource.Type else {
            fatalError("\(type) must be registered before it is used")
        }
        let resource = try made.init(compositor: self) as! R
        resources[ObjectIdentifier(type)] = resource
        return resource
    }

    /// Puts in a resource that is made with what its type cannot make it
    /// with, such as a font.
    func register<R: GraphicsResource>(_ resource: R) {
        resources[ObjectIdentifier(R.self)] = resource
    }

    // MARK: Recording

    /// Starts a frame's display list.
    func beginFrame() {
        entries.removeAll(keepingCapacity: true)
        clipStack.removeAll()
        for resource in resources.values {
            resource.beginFrame()
        }
    }

    /// Records `item` of `kind`, under the clip at this point.
    func draw<K: DrawingKind>(_ kind: K.Type, _ item: K.Item) {
        let id = ObjectIdentifier(kind)
        if kinds[id] == nil {
            kinds[id] = KindFunctions(kind, compositor: self)
        }
        entries.append(Entry(kind: id, item: item, clip: clipStack.last))
    }

    /// The clip, in points, that what is recorded is in, if any.
    var clip: Rect? { clipStack.last }

    /// Records what `body` records clipped to `rect` in points, and to the
    /// clip it is already in.
    func clipping<T>(_ rect: Rect, _ body: () throws -> T) rethrows -> T {
        pushClip(rect)
        defer { popClip() }
        return try body()
    }

    /// Clips what is recorded until `popClip()` to `rect` in points, and to
    /// the clip it is already in.
    func pushClip(_ rect: Rect) {
        clipStack.append(clipStack.last.map { $0.intersection(rect) } ?? rect)
    }

    func popClip() {
        clipStack.removeLast()
    }

    // MARK: Compositing

    /// Runs the display list into `surface`, `width` by `height` pixels,
    /// cleared to `clearColor`, then has `present` copy what was drawn onto
    /// it, and ends the frame.
    func render<Present: DrawingKind>(
        into surface: TextureView, width: UInt32, height: UInt32, clearColor: Color,
        encoder: CommandEncoder, present: Present.Type
    ) throws where Present.Item == TextureView {
        let target = try target(width: width, height: height)
        let size = (width: Float(width), height: Float(height))
        let queue = device.getQueue()

        // Adjacent items of a kind under one clip are a group, but for kinds
        // that read their backdrop, whose items are each one.
        var groups: [(kind: ObjectIdentifier, clip: Rect?, items: [Any])] = []
        for entry in entries {
            if let last = groups.last, last.kind == entry.kind, last.clip == entry.clip,
                !kinds[entry.kind]!.readsBackdrop
            {
                groups[groups.count - 1].items.append(entry.item)
            } else {
                groups.append((entry.kind, entry.clip, [entry.item]))
            }
        }
        let prepareContext = PrepareContext(device: device, queue: queue, width: size.width, height: size.height)
        let prepared = try groups.map { try kinds[$0.kind]!.prepare($0.items, prepareContext) }

        func beginPass(clearing: Bool) -> RenderPassEncoder {
            try! encoder.beginRenderPass(
                descriptor: RenderPassDescriptor(
                    colorAttachments: [
                        RenderPassColorAttachment(
                            view: target.view, loadOp: clearing ? .clear : .load, storeOp: .store,
                            clearValue: clearColor)
                    ]))
        }
        var pass = beginPass(clearing: true)
        for (group, prepared) in zip(groups, prepared) {
            let functions = kinds[group.kind]!
            if functions.readsBackdrop {
                pass.end()
                try functions.encodeOffscreen(
                    prepared,
                    OffscreenContext(
                        device: device, encoder: encoder, backdrop: target.view, width: size.width,
                        height: size.height))
                pass = beginPass(clearing: false)
            }
            if let clip = group.clip?.scaled(by: scale).intersection(Rect(x: 0, y: 0, width: size.width, height: size.height)) {
                pass.setScissorRect(
                    x: UInt32(clip.x.rounded()), y: UInt32(clip.y.rounded()), width: UInt32(clip.width.rounded()),
                    height: UInt32(clip.height.rounded()))
            }
            try functions.encode(prepared, EncodeContext(device: device, pass: pass, width: size.width, height: size.height))
            pass.setViewport(x: 0, y: 0, width: size.width, height: size.height, minDepth: 0, maxDepth: 1)
            pass.setScissorRect(x: 0, y: 0, width: width, height: height)
        }
        pass.end()

        // What was drawn, onto the surface.
        let presentFunctions = KindFunctions(present, compositor: self)
        let presentPrepared = try presentFunctions.prepare([target.view], prepareContext)
        let surfacePass = try encoder.beginRenderPass(
            descriptor: RenderPassDescriptor(
                colorAttachments: [
                    RenderPassColorAttachment(view: surface, loadOp: .clear, storeOp: .store, clearValue: clearColor)
                ]))
        try presentFunctions.encode(
            presentPrepared, EncodeContext(device: device, pass: surfacePass, width: size.width, height: size.height))
        surfacePass.end()

        for resource in resources.values {
            resource.endFrame()
        }
    }

    private func target(width: UInt32, height: UInt32) throws -> (texture: Texture, view: TextureView, width: UInt32, height: UInt32) {
        if let target, target.width == width, target.height == height {
            return target
        }
        let texture = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "frame", usage: [.renderAttachment, .textureBinding], dimension: .`2D`,
                size: Extent3D(width: width, height: height, depthOrArrayLayers: 1), format: format))
        let target = (texture, try texture.createView(), width, height)
        self.target = target
        return target
    }
}

private struct Entry {
    var kind: ObjectIdentifier
    var item: Any
    var clip: Rect?
}

// A kind's functions with its types erased, and its resource found.
@MainActor
private struct KindFunctions {
    let readsBackdrop: Bool
    let prepare: ([Any], PrepareContext) throws -> Any
    let encodeOffscreen: (Any, OffscreenContext) throws -> Void
    let encode: (Any, EncodeContext) throws -> Void

    init<K: DrawingKind>(_ kind: K.Type, compositor: Compositor) {
        readsBackdrop = K.readsBackdrop
        prepare = { items, context in
            try K.prepare(items.map { $0 as! K.Item }, resource: compositor.resource(K.Resource.self), in: context)
        }
        encodeOffscreen = { prepared, context in
            try K.encodeOffscreen(prepared as! K.Prepared, resource: compositor.resource(K.Resource.self), in: context)
        }
        encode = { prepared, context in
            try K.encode(prepared as! K.Prepared, resource: compositor.resource(K.Resource.self), in: context)
        }
    }
}
