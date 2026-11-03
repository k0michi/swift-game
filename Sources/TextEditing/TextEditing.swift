// Editing one line of text: where the selection's two ends are, and what
// typing, deleting and moving do to the text and to them. Positions count
// Characters, grapheme clusters, so that no edit splits an emoji or a
// letter from its accents.

/// Text with a selection, which is a caret when its ends are one. The anchor
/// is where the selection began, and stays as Shift extends it; the head is
/// where the caret is.
public struct TextEditing: Equatable, Sendable {
    public var text: String {
        didSet {
            anchor = min(anchor, text.count)
            head = min(head, text.count)
        }
    }
    public private(set) var anchor: Int
    public private(set) var head: Int

    /// `text` with the caret at its end.
    public init(_ text: String = "") {
        self.text = text
        anchor = text.count
        head = text.count
    }

    /// The selected Characters, from the first end to the last.
    public var selection: Range<Int> {
        min(anchor, head)..<max(anchor, head)
    }

    public var selectedText: String {
        String(text[index(selection.lowerBound)..<index(selection.upperBound)])
    }

    /// Puts the head at `position`, and the anchor too unless `extending`.
    public mutating func moveCaret(to position: Int, extending: Bool = false) {
        head = max(0, min(position, text.count))
        if !extending {
            anchor = head
        }
    }

    public mutating func selectAll() {
        anchor = 0
        head = text.count
    }

    /// Replaces the selection with `string`, with the caret after it.
    public mutating func insert(_ string: String) {
        let range = selection
        text.replaceSubrange(index(range.lowerBound)..<index(range.upperBound), with: string)
        moveCaret(to: range.lowerBound + string.count)
    }

    /// Deletes the selection, or the Character before the caret.
    public mutating func deleteBackward() {
        if selection.isEmpty && head > 0 {
            anchor = head - 1
        }
        insert("")
    }

    /// Deletes the selection, or the Character after the caret.
    public mutating func deleteForward() {
        if selection.isEmpty && head < text.count {
            anchor = head + 1
        }
        insert("")
    }

    /// Moves the caret a Character back, or, without `extending`, to the
    /// selection's start.
    public mutating func moveLeft(extending: Bool = false) {
        if !extending && !selection.isEmpty {
            moveCaret(to: selection.lowerBound)
        } else {
            moveCaret(to: head - 1, extending: extending)
        }
    }

    /// Moves the caret a Character on, or, without `extending`, to the
    /// selection's end.
    public mutating func moveRight(extending: Bool = false) {
        if !extending && !selection.isEmpty {
            moveCaret(to: selection.upperBound)
        } else {
            moveCaret(to: head + 1, extending: extending)
        }
    }

    public mutating func moveToStart(extending: Bool = false) {
        moveCaret(to: 0, extending: extending)
    }

    public mutating func moveToEnd(extending: Bool = false) {
        moveCaret(to: text.count, extending: extending)
    }

    /// Where the Character at `position` begins in the text.
    public func index(_ position: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: position)
    }
}
