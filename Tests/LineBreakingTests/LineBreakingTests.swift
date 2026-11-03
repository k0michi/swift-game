import Foundation
import Testing

@testable import LineBreaking

// Unicode's own tests of UAX #14, LineBreakTest.txt of the Unicode Character
// Database 18.0.0: each line is code points with ÷ where a line may break and
// × where it may not, between them and at both ends. Those with surrogates,
// which are no Unicode.Scalar, are left out.
private let cases: [(line: Int, scalars: [Unicode.Scalar], breaks: [Bool], text: String)] = {
    let path = Bundle.module.path(forResource: "LineBreakTest", ofType: "txt", inDirectory: "Resources")!
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { number, line in
        let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fields = content.split(whereSeparator: \.isWhitespace)
        guard !fields.isEmpty else { return nil }
        var scalars: [Unicode.Scalar] = []
        var breaks: [Bool] = []
        for field in fields {
            switch field {
            case "÷": breaks.append(true)
            case "×": breaks.append(false)
            default:
                guard let scalar = Unicode.Scalar(UInt32(field, radix: 16)!) else { return nil }
                scalars.append(scalar)
            }
        }
        // Without the start and the end, which UAX #14 never and always breaks.
        return (number + 1, scalars, Array(breaks.dropFirst().dropLast()), String(line))
    }
}()

@Suite("UAX #14")
struct LineBreakingTests {
    @Test
    func passesUnicodesTests() {
        #expect(cases.count > 19_000)
        var failures: [String] = []
        for (line, scalars, expected, text) in cases {
            let breaks = lineBreaks(scalars).map { $0 != .prohibited }
            if breaks != expected {
                failures.append("line \(line): \(text)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(cases.count) failed:\n\(failures.prefix(20).joined(separator: "\n"))")
    }

    @Test
    func breaksMandatorilyAfterNewlines() {
        // a, LF, b, CR, LF, c.
        #expect(
            lineBreaks(Array("a\nb\r\nc".unicodeScalars))
                == [.prohibited, .mandatory, .prohibited, .prohibited, .mandatory])
    }

    @Test
    func choosesWhetherSmallKanaBeginLines() {
        // あ, then ぁ, which is CJ.
        let scalars: [Unicode.Scalar] = ["\u{3042}", "\u{3041}"]
        #expect(lineBreaks(scalars, strictness: .strict) == [.prohibited])
        #expect(lineBreaks(scalars, strictness: .normal) == [.allowed])
    }
}
