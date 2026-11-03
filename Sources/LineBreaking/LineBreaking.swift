// The Unicode Line Breaking Algorithm, UAX #14 revision 57, for Unicode
// 18.0.0: where a line may break, must break, or must not, in text.

/// What UAX #14 says of the place between two characters.
public enum LineBreak: Sendable, Equatable {
    /// A line ends here, as after a newline.
    case mandatory
    /// A line may end here.
    case allowed
    /// A line must not end here.
    case prohibited
}

/// Whether small kana and the prolonged sound mark (Line_Break=CJ) may begin
/// a line in Japanese, as CSS's `line-break: strict` and `normal` choose. UAX
/// #14 leaves it to tailoring, and resolves them as nonstarters by default.
public enum LineBreakStrictness: Sendable {
    /// They may not, as UAX #14 does by default.
    case strict
    /// They may, as ideographs do.
    case normal
}

/// For each of `scalars` after the first, what UAX #14 says of the place
/// before it. The end of the text is always a break.
public func lineBreaks(_ scalars: [Unicode.Scalar], strictness: LineBreakStrictness = .strict) -> [LineBreak] {
    guard scalars.count > 1 else { return [] }
    let original = scalars.map(properties)

    // LB1: resolve the classes that depend on what is outside the algorithm.
    var resolved = original.map { properties -> Properties in
        var properties = properties
        switch properties.lineBreak {
        case .ai, .sg, .xx: properties.lineBreak = .al
        case .sa: properties.lineBreak = properties.category == .mn || properties.category == .mc ? .cm : .al
        case .cj: properties.lineBreak = strictness == .strict ? .ns : .id
        default: break
        }
        return properties
    }

    // LB9 and LB10: a combining mark or a zero width joiner after a base takes
    // its properties, and is no place to break; one with no base is a letter.
    var absorbed = [Bool](repeating: false, count: scalars.count)
    var base: Int?
    for index in scalars.indices {
        if resolved[index].lineBreak == .cm || resolved[index].lineBreak == .zwj {
            if let base {
                absorbed[index] = true
                resolved[index] = resolved[base]
                continue
            }
            resolved[index] = Properties(lineBreak: .al, eastAsian: false, pictographic: false, category: .other)
        }
        base = [.bk, .cr, .lf, .nl, .sp, .zw].contains(resolved[index].lineBreak) ? nil : index
    }

    // The rules after LB9 see only the bases.
    let items = scalars.indices.filter { !absorbed[$0] }
    var itemIndex = [Int](repeating: 0, count: scalars.count)
    for (item, index) in items.enumerated() {
        itemIndex[index] = item
    }
    let context = Context(scalars: scalars, items: items, properties: items.map { resolved[$0] })

    return (1..<scalars.count).map { index in
        // LB8a, before LB9: no break after a zero width joiner, which may
        // itself be part of a combining sequence.
        if absorbed[index] || original[index - 1].lineBreak == .zwj {
            return .prohibited
        }
        return context.lineBreak(before: itemIndex[index])
    }
}

// What the rules look at in each base, and around it.
private struct Context {
    let scalars: [Unicode.Scalar]
    let items: [Int]
    let properties: [Properties]

    func lineBreakClass(_ item: Int) -> LineBreakClass? {
        properties.indices.contains(item) ? properties[item].lineBreak : nil
    }

    // The item before `item` and any spaces between them.
    func skippingSpaces(before item: Int) -> Int {
        var item = item - 1
        while item >= 0 && properties[item].lineBreak == .sp {
            item -= 1
        }
        return item
    }

    // Whether `item` ends NU (SY | IS)*.
    func endsNumber(_ item: Int) -> Bool {
        var item = item
        while item >= 0 && [.sy, .is].contains(properties[item].lineBreak) {
            item -= 1
        }
        return item >= 0 && properties[item].lineBreak == .nu
    }

    // An aksara, or U+25CC DOTTED CIRCLE standing for one, for LB28a.
    func isAksara(_ item: Int) -> Bool {
        properties.indices.contains(item)
            && (properties[item].lineBreak == .ak || scalars[items[item]] == "\u{25CC}")
    }

    func isAksaraOrStacker(_ item: Int) -> Bool {
        isAksara(item) || lineBreakClass(item) == .as
    }

    func isEastAsian(_ item: Int) -> Bool {
        properties.indices.contains(item) && properties[item].eastAsian
    }

    // The rules from LB4 on, but LB8a and LB9, in order, before `item`.
    func lineBreak(before item: Int) -> LineBreak {
        let a = properties[item - 1].lineBreak
        let b = properties[item].lineBreak
        let next = lineBreakClass(item + 1)
        let beforeA = lineBreakClass(item - 2)

        // LB4 to LB7: hard line breaks, and spaces.
        if a == .bk { return .mandatory }
        if a == .cr && b == .lf { return .prohibited }
        if [.cr, .lf, .nl].contains(a) { return .mandatory }
        if [.bk, .cr, .lf, .nl].contains(b) { return .prohibited }
        if b == .sp || b == .zw { return .prohibited }
        // LB8: after a zero width space and any spaces after it.
        let beforeSpaces = skippingSpaces(before: item)
        if beforeSpaces >= 0 && properties[beforeSpaces].lineBreak == .zw { return .allowed }
        // LB11 to LB12a: word joiners and non-breaking characters.
        if a == .wj || b == .wj { return .prohibited }
        if a == .gl { return .prohibited }
        if b == .gl && ![.sp, .hy, .hh].contains(a) { return .prohibited }
        // LB13 and LB14: closing and opening punctuation.
        if [.cl, .cp, .ex, .sy].contains(b) { return .prohibited }
        if beforeSpaces >= 0 && properties[beforeSpaces].lineBreak == .op { return .prohibited }
        // LB15a: after initial quotation at the start of a quotation.
        if beforeSpaces >= 0 && properties[beforeSpaces].lineBreak == .qu
            && properties[beforeSpaces].category == .pi
        {
            let before = lineBreakClass(beforeSpaces - 1)
            if before == nil || [.bk, .cr, .lf, .nl, .op, .qu, .gl, .sp, .zw].contains(before!) {
                return .prohibited
            }
        }
        // LB15b: before final quotation at the end of a quotation.
        if b == .qu && properties[item].category == .pf
            && (next == nil
                || [.sp, .gl, .wj, .cl, .qu, .cp, .ex, .is, .sy, .bk, .cr, .lf, .nl, .zw].contains(next!))
        {
            return .prohibited
        }
        // LB15c and LB15d: decimal marks and infix separators.
        if a == .sp && b == .is && next == .nu { return .allowed }
        if b == .is { return .prohibited }
        // LB16 and LB17: closing punctuation before nonstarters, and ‘——’.
        if beforeSpaces >= 0 && [.cl, .cp].contains(properties[beforeSpaces].lineBreak) && b == .ns {
            return .prohibited
        }
        if beforeSpaces >= 0 && properties[beforeSpaces].lineBreak == .b2 && b == .b2 { return .prohibited }
        // LB18: after spaces.
        if a == .sp { return .allowed }
        // LB19 and LB19a: quotation marks.
        if b == .qu && properties[item].category != .pi { return .prohibited }
        if a == .qu && properties[item - 1].category != .pf { return .prohibited }
        if b == .qu && (!isEastAsian(item - 1) || !isEastAsian(item + 1)) { return .prohibited }
        if a == .qu && (!isEastAsian(item) || !isEastAsian(item - 2)) { return .prohibited }
        // LB20 to LB22: conditional breaks, hyphens, nonstarters and ellipses.
        if a == .cb || b == .cb { return .allowed }
        if [.hy, .hh].contains(a) && [.al, .hl].contains(b)
            && (beforeA == nil || [.bk, .cr, .lf, .nl, .sp, .zw, .cb, .gl].contains(beforeA!))
        {
            return .prohibited
        }
        if [.ba, .hh, .hy, .ns].contains(b) || a == .bb { return .prohibited }
        if [.hy, .hh].contains(a) && beforeA == .hl && b != .hl { return .prohibited }
        if a == .sy && b == .hl { return .prohibited }
        if b == .in { return .prohibited }
        // LB23 to LB25: numbers, and what goes before and after them.
        if [.al, .hl].contains(a) && b == .nu || a == .nu && [.al, .hl].contains(b) { return .prohibited }
        if a == .pr && [.id, .eb, .em].contains(b) || [.id, .eb, .em].contains(a) && b == .po { return .prohibited }
        if [.pr, .po].contains(a) && [.al, .hl].contains(b) || [.al, .hl].contains(a) && [.pr, .po].contains(b) {
            return .prohibited
        }
        if [.cl, .cp].contains(a) && [.po, .pr].contains(b) && endsNumber(item - 2) { return .prohibited }
        if [.po, .pr].contains(b) && endsNumber(item - 1) { return .prohibited }
        if [.po, .pr].contains(a) && b == .op
            && (next == .nu || next == .is && lineBreakClass(item + 2) == .nu)
        {
            return .prohibited
        }
        if [.po, .pr, .hy, .is].contains(a) && b == .nu { return .prohibited }
        if b == .nu && endsNumber(item - 1) { return .prohibited }
        // LB26 and LB27: Korean syllable blocks.
        if a == .jl && [.jl, .jv, .h2, .h3].contains(b) || [.jv, .h2].contains(a) && [.jv, .jt].contains(b)
            || [.jt, .h3].contains(a) && b == .jt
        {
            return .prohibited
        }
        if [.jl, .jv, .jt, .h2, .h3].contains(a) && b == .po || a == .pr && [.jl, .jv, .jt, .h2, .h3].contains(b) {
            return .prohibited
        }
        // LB28 and LB28a: letters, and the orthographic syllables of Brahmic
        // scripts.
        if [.al, .hl].contains(a) && [.al, .hl].contains(b) { return .prohibited }
        if a == .ap && isAksaraOrStacker(item) { return .prohibited }
        if isAksaraOrStacker(item - 1) && [.vf, .vi].contains(b) { return .prohibited }
        if isAksaraOrStacker(item - 2) && a == .vi && isAksara(item) { return .prohibited }
        if isAksaraOrStacker(item - 1) && isAksaraOrStacker(item) && next == .vf { return .prohibited }
        // LB29 and LB30: punctuation and parentheses with letters and numbers.
        if a == .is && [.al, .hl].contains(b) { return .prohibited }
        if [.al, .hl, .nu].contains(a) && b == .op && !isEastAsian(item) { return .prohibited }
        if a == .cp && !isEastAsian(item - 1) && [.al, .hl, .nu].contains(b) { return .prohibited }
        // LB30a: regional indicators in pairs.
        if a == .ri && b == .ri {
            var count = 0
            var before = item - 1
            while before >= 0 && properties[before].lineBreak == .ri {
                count += 1
                before -= 1
            }
            if count % 2 == 1 { return .prohibited }
        }
        // LB30b: emoji bases and modifiers.
        if b == .em
            && (a == .eb || properties[item - 1].pictographic && properties[item - 1].category == .cn)
        {
            return .prohibited
        }
        // LB31.
        return .allowed
    }
}

// What the rules need of a code point.
struct Properties {
    enum Category: UInt8 {
        case other, mn, mc, pi, pf, cn
    }

    var lineBreak: LineBreakClass
    /// Whether its East_Asian_Width is F, W or H.
    var eastAsian: Bool
    var pictographic: Bool
    var category: Category
}

// From the run of lineBreakProperties that `scalar` is in.
func properties(_ scalar: Unicode.Scalar) -> Properties {
    let key = scalar.value << 11 | 0x7FF
    var low = 0
    var high = lineBreakProperties.count
    while low < high {
        let middle = (low + high) / 2
        if lineBreakProperties[middle] <= key {
            low = middle + 1
        } else {
            high = middle
        }
    }
    let packed = lineBreakProperties[low - 1]
    return Properties(
        lineBreak: LineBreakClass(rawValue: UInt8(packed >> 5 & 0x3F))!,
        eastAsian: packed >> 4 & 1 == 1,
        pictographic: packed >> 3 & 1 == 1,
        category: Properties.Category(rawValue: UInt8(packed & 0x7)) ?? .other)
}
