#!/usr/bin/env swift

// Writes Sources/LineBreaking/Generated/LineBreakProperties.swift: what UAX #14
// needs of each code point, from the Unicode Character Database of the version
// below, which UAX #14 revision 57 is for. Run it with
// `swift scripts/generate-line-break-properties.swift` after changing the
// version, and commit what it writes. It downloads the database's files.

import Foundation

let version = "18.0.0"
let base = "https://www.unicode.org/Public/\(version)/ucd"

// The Line_Break classes, in the order of their raw values.
let classes = [
    "AI", "AK", "AL", "AP", "AS", "B2", "BA", "BB", "BK", "CB", "CJ", "CL", "CM", "CP", "CR", "EB", "EM", "EX", "GL",
    "H2", "H3", "HH", "HL", "HY", "ID", "IN", "IS", "JL", "JT", "JV", "LF", "NL", "NS", "NU", "OP", "PO", "PR", "QU",
    "RI", "SA", "SG", "SP", "SY", "VF", "VI", "WJ", "XX", "ZW", "ZWJ",
]
// The General_Category values the rules look at, and the rest as 0.
let categories = ["Mn": 1, "Mc": 2, "Pi": 3, "Pf": 4, "Cn": 5]

let codePoints = 0x110000

// The value of each code point in a file of `code point(s) ; value` lines,
// the values not listed being `missing`.
func read(_ file: String, missing: String, value: (String) -> String? = { $0 }) throws -> [String] {
    let url = URL(string: "\(base)/\(file)")!
    let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    var values = [String](repeating: missing, count: codePoints)
    for line in text.split(separator: "\n") {
        let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fields = content.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2, let property = value(fields[1]) else { continue }
        let bounds = fields[0].split(separator: ".", omittingEmptySubsequences: true).map { Int($0, radix: 16)! }
        for codePoint in bounds[0]...(bounds.last!) {
            values[codePoint] = property
        }
    }
    return values
}

let lineBreak = try read("LineBreak.txt", missing: "XX")
let eastAsianWidth = try read("EastAsianWidth.txt", missing: "N")
let extendedPictographic = try read("emoji/emoji-data.txt", missing: "") {
    $0 == "Extended_Pictographic" ? "Y" : nil
}
let generalCategory = try read("extracted/DerivedGeneralCategory.txt", missing: "Cn")

// Each code point's properties packed in 11 bits: the class in 6, then
// whether its East_Asian_Width is F, W or H, whether it is
// Extended_Pictographic, and the General_Category in 3. Consecutive code
// points with the same properties are one entry, its first code point shifted
// above them.
func packed(_ codePoint: Int) -> UInt32 {
    guard let lineBreakClass = classes.firstIndex(of: lineBreak[codePoint]) else {
        fatalError("Unknown Line_Break class \(lineBreak[codePoint])")
    }
    let eastAsian: UInt32 = ["F", "W", "H"].contains(eastAsianWidth[codePoint]) ? 1 : 0
    let pictographic: UInt32 = extendedPictographic[codePoint] == "Y" ? 1 : 0
    let category = UInt32(categories[generalCategory[codePoint]] ?? 0)
    return UInt32(lineBreakClass) << 5 | eastAsian << 4 | pictographic << 3 | category
}

var entries: [UInt32] = []
var previous: UInt32?
for codePoint in 0..<codePoints {
    let properties = packed(codePoint)
    if properties != previous {
        entries.append(UInt32(codePoint) << 11 | properties)
        previous = properties
    }
}

var output = """
    // Written by scripts/generate-line-break-properties.swift from the Unicode
    // Character Database \(version). Do not change it by hand.

    /// A Line_Break class.
    enum LineBreakClass: UInt8, Sendable {
        case \(classes.map { ["as", "in", "is"].contains($0.lowercased()) ? "`\($0.lowercased())`" : $0.lowercased() }.joined(separator: ", "))
    }

    /// The first code point of each run of code points with the same
    /// properties, shifted left by 11, above the run's properties: the class in
    /// 6 bits, whether the East_Asian_Width is F, W or H, whether it is
    /// Extended_Pictographic, and the General_Category in 3, which is 1 for Mn,
    /// 2 for Mc, 3 for Pi, 4 for Pf, 5 for Cn and 0 for the rest.
    let lineBreakProperties: [UInt32] = [

    """
for row in stride(from: 0, to: entries.count, by: 8) {
    let values = entries[row..<min(row + 8, entries.count)].map { "0x" + String($0, radix: 16, uppercase: true) }
    output += "    " + values.joined(separator: ", ") + ",\n"
}
output += "]\n"

let destination = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/LineBreaking/Generated")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
try output.write(
    to: destination.appendingPathComponent("LineBreakProperties.swift"), atomically: true, encoding: .utf8)
print("\(entries.count) runs")
