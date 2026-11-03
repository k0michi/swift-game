import LineBreaking

// Where text breaks into lines, by UAX #14.

struct LineBreaks {
    // The UTF-8 offsets of what may begin a line, and of what must.
    var allowed: Set<Int>
    var mandatory: Set<Int>
}

func lineBreaks(_ text: String) -> LineBreaks {
    let scalars = Array(text.unicodeScalars)
    var breaks = LineBreaks(allowed: [], mandatory: [])
    var offset = scalars.first.map(UTF8.width) ?? 0
    for (index, lineBreak) in LineBreaking.lineBreaks(scalars).enumerated() {
        switch lineBreak {
        case .mandatory: breaks.mandatory.insert(offset)
        case .allowed: breaks.allowed.insert(offset)
        case .prohibited: break
        }
        offset += UTF8.width(scalars[index + 1])
    }
    return breaks
}

private func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\u{3000}"
}

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
            .unicodeScalars.allSatisfy { isSpace($0) || $0 == "\n" || $0 == "\r" }
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
