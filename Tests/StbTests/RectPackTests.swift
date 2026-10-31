import Testing

@testable import StbRectPack

@Suite("stb_rect_pack")
struct RectPackTests {
    @Test
    func packsWithoutOverlap() {
        let context = initTarget(width: 10, height: 10)
        var rects = [Rect(id: 0, w: 6, h: 4), Rect(id: 1, w: 4, h: 10), Rect(id: 2, w: 6, h: 6)]
        #expect(packRects(context: context, rects: &rects))
        #expect(rects.map(\.id) == [0, 1, 2])
        #expect(rects.allSatisfy { $0.wasPacked && $0.x >= 0 && $0.y >= 0 && $0.x + $0.w <= 10 && $0.y + $0.h <= 10 })
        for (index, a) in rects.enumerated() {
            for b in rects[(index + 1)...] {
                let apart = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y
                #expect(apart, "\(a) overlaps \(b)")
            }
        }
    }

    @Test
    func saysWhatDidNotFit() {
        let context = initTarget(width: 8, height: 8)
        setupHeuristic(context: context, heuristic: .skylineBFSortHeight)
        var rects = [Rect(id: 0, w: 4, h: 4), Rect(id: 1, w: 9, h: 2)]
        #expect(!packRects(context: context, rects: &rects))
        #expect(rects[0].wasPacked)
        #expect(!rects[1].wasPacked)
    }
}
