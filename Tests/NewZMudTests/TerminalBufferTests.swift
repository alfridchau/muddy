import XCTest
@testable import NewZMud

final class TerminalBufferTests: XCTestCase {
    func testChineseOccupiesTwoCellsAndCombiningMarksStayTogether() {
        var terminal = TerminalBuffer()
        terminal.feed("A中B e\u{301} 👩‍💻")
        XCTAssertEqual(terminal.rows[0].cells[1].text, "中")
        XCTAssertEqual(terminal.rows[0].cells[2].width, 0)
        XCTAssertEqual(terminal.rows[0].cells[3].text, "B")
        XCTAssertEqual(terminal.cursorColumn, 9)
        XCTAssertEqual(terminal.rows[0].text, "A中B é 👩‍💻")
    }

    func testCarriageReturnAndEraseReplaceAProgressLine() {
        var terminal = TerminalBuffer()
        terminal.feed("Loading 100%\rReady\u{1B}[K")
        XCTAssertEqual(terminal.rows[0].text, "Ready")
        XCTAssertEqual(terminal.cursorColumn, 5)
    }

    func testEmojiPresentationWidensThePreviousCell() {
        var terminal = TerminalBuffer()
        terminal.feed("❤")
        terminal.feed("\u{FE0F}X")
        XCTAssertEqual(terminal.rows[0].cells[0].text, "❤️")
        XCTAssertEqual(terminal.rows[0].cells[0].width, 2)
        XCTAssertEqual(terminal.rows[0].cells[2].text, "X")
    }

    func testFragmentedSGRPreservesTrueColorAndResetsAttributes() {
        var terminal = TerminalBuffer()
        terminal.feed("\u{1B}[1;38;2;10;")
        terminal.feed("20;30m侠\u{1B}[0mX")
        XCTAssertEqual(terminal.rows[0].cells[0].style.foreground, .rgb(10, 20, 30))
        XCTAssertTrue(terminal.rows[0].cells[0].style.bold)
        XCTAssertEqual(terminal.rows[0].cells[2].style, CellStyle())
    }

    func testCursorEditsDoNotLeaveHalfOfAWideGlyph() {
        var terminal = TerminalBuffer()
        terminal.feed("A中B\u{1B}[3GX")
        XCTAssertEqual(terminal.rows[0].text, "A XB")
        XCTAssertTrue(terminal.rows[0].cells.allSatisfy { $0.width > 0 })
    }

    func testAlternateScreenRestoresScrollbackAndCursor() {
        var terminal = TerminalBuffer()
        terminal.feed("江湖\r\n客店")
        let before = terminal.plainText
        let column = terminal.cursorColumn
        terminal.feed("\u{1B}[?1049h\u{1B}[2J\u{1B}[HMenu")
        XCTAssertTrue(terminal.isAlternateScreen)
        XCTAssertEqual(terminal.rows[0].text, "Menu")
        terminal.feed("\u{1B}[?1049l")
        XCTAssertFalse(terminal.isAlternateScreen)
        XCTAssertEqual(terminal.plainText, before)
        XCTAssertEqual(terminal.cursorColumn, column)
    }

    func testAutomaticWrapDoesNotSplitTriggerLines() {
        var terminal = TerminalBuffer()
        terminal.resize(columns: 20, rows: 5)
        let text = String(repeating: "中", count: 15)
        XCTAssertEqual(terminal.feed(text + "\r\n"), [text])
        XCTAssertEqual(terminal.rows[0].text, String(repeating: "中", count: 10))
        XCTAssertEqual(terminal.rows[1].text, String(repeating: "中", count: 5))
    }

    func testOSCIsIgnoredAndScrollbackIsBounded() {
        var terminal = TerminalBuffer()
        terminal.feed("\u{1B}]0;hidden title\u{7}visible\r\n")
        XCTAssertEqual(terminal.rows[0].text, "visible")
        terminal.feed(String(repeating: "line\r\n", count: 2200))
        XCTAssertLessThanOrEqual(terminal.rows.count, 2030)
        XCTAssertEqual(terminal.rows.last?.text, "")
    }
}
