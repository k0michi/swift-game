// Where text breaks into lines: a simplified Unicode line breaking (UAX #14)
// for English and Japanese. A line may break after spaces and between CJK
// characters, but never before closing punctuation, small kana and the like,
// nor after opening brackets (kinsoku), nor before a combining mark. It must
// break after a newline.

struct LineBreaks {
    // The UTF-8 offsets of what may begin a line, and of what must.
    var allowed: Set<Int>
    var mandatory: Set<Int>
}

func lineBreaks(_ text: String) -> LineBreaks {
    var breaks = LineBreaks(allowed: [], mandatory: [])
    var offset = 0
    var previous: Unicode.Scalar?
    for scalar in text.unicodeScalars {
        if let previous {
            if previous == "\n" {
                breaks.mandatory.insert(offset)
            } else if isBreakAllowed(after: previous, before: scalar) {
                breaks.allowed.insert(offset)
            }
        }
        offset += UTF8.width(scalar)
        previous = scalar
    }
    return breaks
}

private func isBreakAllowed(after previous: Unicode.Scalar, before next: Unicode.Scalar) -> Bool {
    // Spaces stay at the end of the line they follow.
    if isSpace(next) || isCombining(next) {
        return false
    }
    if cannotBeginLine.contains(next) || cannotEndLine.contains(previous) {
        return false
    }
    return isSpace(previous) || isCJK(previous) || isCJK(next)
}

private func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\u{3000}"
}

private func isCombining(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: true
    default: scalar.properties.isVariationSelector
    }
}

private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x2E80...0x2FFF,  // Radicals and ideographic description
        0x3000...0x30FF,  // CJK symbols and punctuation, hiragana and katakana
        0x3100...0x31FF,  // Bopomofo, kanbun and katakana's extension
        0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,  // Ideographs
        0xFF00...0xFFEF,  // Halfwidth and fullwidth forms
        0x20000...0x3FFFF:  // Ideographs beyond the basic plane
        true
    default:
        false
    }
}

// Closing brackets and quotes, punctuation, prolonged sound marks, iteration
// marks and small kana.
private let cannotBeginLine = Set(
    (")]}）〕］｝〉》」』】〙〗〟’”｠»、。，．,.:;：；!?！？‼⁇⁈⁉・･ー〜～ゝゞヽヾ々〻"
        + "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ").unicodeScalars)

// Opening brackets and quotes.
private let cannotEndLine = Set("([{（〔［｛〈《「『【〘〖〝‘“｟«".unicodeScalars)

/// The lines of `text` no wider than `maximum`, from where its clusters
/// begin, by UTF-8 offset, and their pens' x, and its `width`, all in the same
/// units. Each line is a range of UTF-8 offsets, without the spaces and the
/// newline at its end. A line breaks at the last place it may before it is
/// too wide, or, where it may nowhere, before the cluster that makes it so.
func wrap(_ text: String, clusters: [(offset: Int, x: Int)], width: Int, maximum: Int?) -> [Range<Int>] {
    let bytes = Array(text.utf8)
    let breaks = lineBreaks(text)
    // Each cluster's start, and the end.
    let starts = clusters + [(offset: bytes.count, x: width)]

    func isBlank(_ cluster: Int) -> Bool {
        String(decoding: bytes[starts[cluster].offset..<starts[cluster + 1].offset], as: UTF8.self)
            .unicodeScalars.allSatisfy { isSpace($0) || $0 == "\n" }
    }
    // The clusters from `first` to before `end`, without those blank at the
    // end: their offsets and how wide they are.
    func trimmed(_ first: Int, _ end: Int) -> (range: Range<Int>, width: Int) {
        var last = end
        while last > first && isBlank(last - 1) {
            last -= 1
        }
        return (starts[first].offset..<starts[last].offset, starts[last].x - starts[first].x)
    }

    var lines: [Range<Int>] = []
    var first = 0
    var lastBreak: Int?
    var cluster = 1
    while cluster < starts.count {
        if let maximum, trimmed(first, cluster).width > maximum, cluster - 1 > first {
            let end = lastBreak ?? cluster - 1
            lines.append(trimmed(first, end).range)
            first = end
            lastBreak = nil
            // The cluster is looked at again, on the new line.
            continue
        }
        if breaks.mandatory.contains(starts[cluster].offset) {
            lines.append(trimmed(first, cluster).range)
            first = cluster
            lastBreak = nil
        } else if breaks.allowed.contains(starts[cluster].offset) {
            lastBreak = cluster
        }
        cluster += 1
    }
    lines.append(trimmed(first, starts.count - 1).range)
    return lines
}
