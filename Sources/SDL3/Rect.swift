import CSDL3

// SDL_Rect
public struct Rect: Equatable, Hashable, Sendable {
    public var x: Int32
    public var y: Int32
    public var w: Int32
    public var h: Int32

    public init(x: Int32, y: Int32, w: Int32, h: Int32) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init(_ rect: SDL_Rect) {
        self.init(x: rect.x, y: rect.y, w: rect.w, h: rect.h)
    }

    var cValue: SDL_Rect {
        SDL_Rect(x: x, y: y, w: w, h: h)
    }
}
