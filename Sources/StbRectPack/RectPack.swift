import CStbRectPack

// stbrp_rect
public struct Rect: Equatable, Sendable {
    public var id: Int32
    public var w: Int32
    public var h: Int32
    public var x: Int32
    public var y: Int32
    public var wasPacked: Bool

    public init(id: Int32, w: Int32, h: Int32) {
        self.id = id
        self.w = w
        self.h = h
        x = 0
        y = 0
        wasPacked = false
    }
}

// STBRP_HEURISTIC_Skyline_*
public enum Heuristic: Int32, Sendable {
    case skylineBLSortHeight = 0
    case skylineBFSortHeight = 1

    public static let skylineDefault = Self.skylineBLSortHeight
}

// stbrp_context with the nodes it packs with, which live as long as it.
public final class Context {
    let pointer: UnsafeMutablePointer<stbrp_context>
    private let nodes: UnsafeMutablePointer<stbrp_node>

    fileprivate init(width: Int32, height: Int32, numNodes: Int32) {
        pointer = .allocate(capacity: 1)
        nodes = .allocate(capacity: Int(max(numNodes, 1)))
        stbrp_init_target(pointer, width, height, nodes, numNodes)
    }

    deinit {
        pointer.deallocate()
        nodes.deallocate()
    }
}

// stbrp_init_target: packs into width x height, with as many nodes as the
// width for the best packing.
public func initTarget(width: Int32, height: Int32, numNodes: Int32? = nil) -> Context {
    precondition(width > 0 && height > 0)
    return Context(width: width, height: height, numNodes: numNodes ?? width)
}

// stbrp_setup_allow_out_of_mem
public func setupAllowOutOfMem(context: Context, allowOutOfMem: Bool) {
    stbrp_setup_allow_out_of_mem(context.pointer, allowOutOfMem ? 1 : 0)
}

// stbrp_setup_heuristic
public func setupHeuristic(context: Context, heuristic: Heuristic) {
    stbrp_setup_heuristic(context.pointer, heuristic.rawValue)
}

// stbrp_pack_rects: places the rects, setting x, y and wasPacked of each,
// and returns whether all of them were.
@discardableResult
public func packRects(context: Context, rects: inout [Rect]) -> Bool {
    var packed = rects.map { stbrp_rect(id: $0.id, w: $0.w, h: $0.h, x: 0, y: 0, was_packed: 0) }
    let all = stbrp_pack_rects(context.pointer, &packed, Int32(packed.count)) != 0
    for index in rects.indices {
        rects[index].x = packed[index].x
        rects[index].y = packed[index].y
        rects[index].wasPacked = packed[index].was_packed != 0
    }
    return all
}
