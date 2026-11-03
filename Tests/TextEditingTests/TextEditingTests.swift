import Testing

@testable import TextEditing

@Suite("Text editing")
struct TextEditingTests {
    @Test
    func typesAndDeletes() {
        var editing = TextEditing()
        editing.insert("abc")
        #expect((editing.text, editing.head) == ("abc", 3))
        editing.deleteBackward()
        editing.insert("d")
        #expect(editing.text == "abd")
        editing.moveToStart()
        editing.deleteForward()
        #expect((editing.text, editing.head) == ("bd", 0))
        editing.deleteBackward()
        #expect(editing.text == "bd")
    }

    @Test
    func editsWholeCharacters() {
        // An emoji of several scalars, and e with a combining acute accent.
        var editing = TextEditing("a👨‍👩‍👧e\u{301}")
        #expect(editing.text.count == 3)
        editing.deleteBackward()
        #expect(editing.text == "a👨‍👩‍👧")
        editing.moveLeft()
        editing.insert("あ")
        #expect(editing.text == "aあ👨‍👩‍👧")
    }

    @Test
    func selectsAndReplaces() {
        var editing = TextEditing("hello world")
        editing.moveToStart()
        for _ in 0..<5 { editing.moveRight(extending: true) }
        #expect((editing.selection, editing.selectedText) == (0..<5, "hello"))
        editing.insert("goodbye")
        #expect((editing.text, editing.head) == ("goodbye world", 7))

        editing.selectAll()
        editing.moveLeft()
        #expect((editing.head, editing.selection) == (0, 0..<0))
        editing.moveToEnd(extending: true)
        editing.deleteBackward()
        #expect(editing.text.isEmpty)
    }

    @Test
    func keepsTheSelectionInTextReplaced() {
        var editing = TextEditing("abcdef")
        editing.text = "ab"
        #expect((editing.anchor, editing.head) == (2, 2))
        editing.moveLeft()
        editing.moveLeft()
        editing.moveLeft()
        #expect(editing.head == 0)
    }
}
