import Foundation

// A small VT-style screen with scrollback. Wide glyphs occupy two grid cells;
// their continuation cells are retained so cursor edits cannot split them.
enum TerminalColor: Equatable {
    case indexed(Int)
    case rgb(Int, Int, Int)
}

struct CellStyle: Equatable {
    var foreground: TerminalColor?
    var background: TerminalColor?
    var bold = false
    var italic = false
    var underline = false
    var inverse = false
}

struct TerminalCell: Equatable {
    var text = " "
    var width = 1
    var style = CellStyle()
}

struct TerminalRow: Equatable {
    var cells: [TerminalCell] = []
    var text: String {
        var result = cells.filter { $0.width > 0 }.map(\.text).joined()
        while result.last == " " { result.removeLast() }
        return result
    }
}

struct TerminalBuffer {
    private enum Escape { case text, start, csi, osc, oscEnd, charset }
    private struct SavedScreen {
        var rows: [TerminalRow]
        var origin: Int
        var row: Int
        var column: Int
        var style: CellStyle
    }

    private(set) var rows = [TerminalRow()]
    private(set) var cursorRow = 0
    private(set) var cursorColumn = 0
    private(set) var columns = 80
    private(set) var height = 30
    private(set) var cursorVisible = true
    private(set) var revision = 0
    private(set) var outputRevision = 0
    private(set) var isAlternateScreen = false
    private var origin = 0
    private var style = CellStyle()
    private var escape = Escape.text
    private var parameters = ""
    private var savedCursor = (row: 0, column: 0)
    private var savedScreen: SavedScreen?
    private var scrollTop = 0
    private var scrollBottom = 29
    private var triggerLine = ""
    private var joinNext = false
    private var regionalIndicator = false
    private let scrollbackLimit = 2000

    var plainLines: [String] { rows.map(\.text) }
    var plainText: String { plainLines.joined(separator: "\n") }

    mutating func resize(columns: Int, rows: Int) {
        self.columns = max(20, min(columns, 500))
        height = max(5, min(rows, 200))
        scrollTop = 0
        scrollBottom = height - 1
        origin = max(origin, cursorRow - height + 1)
        cursorColumn = min(cursorColumn, self.columns - 1)
        revision &+= 1
    }

    mutating func clear() {
        let width = columns
        let screenHeight = height
        let oldRevision = revision
        let oldOutputRevision = outputRevision
        self = TerminalBuffer()
        resize(columns: width, rows: screenHeight)
        revision = oldRevision &+ 1
        outputRevision = oldOutputRevision &+ 1
    }

    @discardableResult
    mutating func feed(_ text: String) -> [String] {
        var completed: [String] = []
        for scalar in text.unicodeScalars {
            let value = scalar.value
            switch escape {
            case .text:
                switch value {
                case 27: escape = .start
                case 13: cursorColumn = 0
                case 10:
                    completed.append(triggerLine)
                    triggerLine = ""
                    lineFeed()
                case 8:
                    cursorColumn = max(0, cursorColumn - 1)
                    if cell(at: cursorColumn).width == 0 { cursorColumn = max(0, cursorColumn - 1) }
                    if !triggerLine.isEmpty { triggerLine.removeLast() }
                case 9:
                    let target = min(columns, ((cursorColumn / 8) + 1) * 8)
                    while cursorColumn < target { put(" ", width: 1) }
                    triggerLine += "\t"
                case 0...31, 127: break
                default:
                    appendScalar(scalar)
                    if triggerLine.count < 16_384 { triggerLine.unicodeScalars.append(scalar) }
                }
            case .start:
                switch value {
                case 91: parameters = ""; escape = .csi
                case 93: escape = .osc
                case 40, 41, 42, 43: escape = .charset
                case 55: savedCursor = (cursorRow, cursorColumn); escape = .text
                case 56: restoreCursor(); escape = .text
                case 68: lineFeed(); escape = .text
                case 69: cursorColumn = 0; lineFeed(); escape = .text
                case 77: reverseIndex(); escape = .text
                case 99: clear()
                default: escape = .text
                }
            case .charset: escape = .text
            case .csi:
                if (64...126).contains(value) {
                    executeCSI(Character(String(scalar)))
                    escape = .text
                } else if parameters.count < 128 {
                    parameters.unicodeScalars.append(scalar)
                } else { escape = .text }
            case .osc:
                if value == 7 { escape = .text }
                else if value == 27 { escape = .oscEnd }
            case .oscEnd:
                if value == 92 || value == 7 { escape = .text }
                else if value != 27 { escape = .osc }
            }
        }
        trimScrollback()
        revision &+= 1
        outputRevision &+= 1
        return completed
    }

    private mutating func appendScalar(_ scalar: Unicode.Scalar) {
        let value = scalar.value
        let width = Self.cellWidth(scalar)
        let isRegional = (0x1F1E6...0x1F1FF).contains(value)
        if width == 0 || joinNext || (isRegional && regionalIndicator) {
            if cursorColumn > 0 {
                let index = min(cursorColumn - 1, columns - 1)
                let lead = cell(at: index).width == 0 ? max(0, index - 1) : index
                ensureRow(cursorRow)
                if rows[cursorRow].cells.indices.contains(lead) {
                    let previous = rows[cursorRow].cells[lead]
                    if value == 0xFE0F && previous.width == 1 && previous.text.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                        let originalStyle = style
                        style = previous.style
                        eraseCell(lead)
                        cursorColumn = lead
                        put(previous.text + String(scalar), width: 2)
                        style = originalStyle
                    } else {
                        rows[cursorRow].cells[lead].text.unicodeScalars.append(scalar)
                    }
                }
            }
            joinNext = value == 0x200D
            if isRegional { regionalIndicator = false }
            return
        }
        joinNext = false
        regionalIndicator = isRegional
        put(String(scalar), width: width)
    }

    static func cellWidth(_ scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        let category = scalar.properties.generalCategory
        if category == .nonspacingMark || category == .enclosingMark || value == 0x200D ||
            (0xFE00...0xFE0F).contains(value) || (0x1F3FB...0x1F3FF).contains(value) { return 0 }
        if value >= 0x1100 && (
            value <= 0x115F || value == 0x2329 || value == 0x232A ||
            (0x2E80...0xA4CF).contains(value) && value != 0x303F ||
            (0xAC00...0xD7A3).contains(value) || (0xF900...0xFAFF).contains(value) ||
            (0xFE10...0xFE19).contains(value) || (0xFE30...0xFE6F).contains(value) ||
            (0xFF00...0xFF60).contains(value) || (0xFFE0...0xFFE6).contains(value) ||
            (0x1F000...0x1FAFF).contains(value) || (0x20000...0x3FFFD).contains(value)
        ) { return 2 }
        return 1
    }

    private mutating func put(_ text: String, width: Int) {
        if cursorColumn + width > columns { cursorColumn = 0; lineFeed() }
        ensureRow(cursorRow)
        ensureCells(cursorColumn + width)
        eraseCell(cursorColumn)
        if width == 2 { eraseCell(cursorColumn + 1) }
        rows[cursorRow].cells[cursorColumn] = TerminalCell(text: text, width: width, style: style)
        if width == 2 {
            rows[cursorRow].cells[cursorColumn + 1] = TerminalCell(text: "", width: 0, style: style)
        }
        cursorColumn += width
    }

    private func cell(at column: Int) -> TerminalCell {
        guard rows.indices.contains(cursorRow), rows[cursorRow].cells.indices.contains(column) else { return TerminalCell() }
        return rows[cursorRow].cells[column]
    }

    private mutating func ensureRow(_ index: Int) {
        while rows.count <= index { rows.append(TerminalRow()) }
    }

    private mutating func ensureCells(_ count: Int) {
        while rows[cursorRow].cells.count < count { rows[cursorRow].cells.append(TerminalCell()) }
    }

    private mutating func eraseCell(_ column: Int) {
        guard rows[cursorRow].cells.indices.contains(column) else { return }
        let existing = rows[cursorRow].cells[column]
        if existing.width == 2, rows[cursorRow].cells.indices.contains(column + 1) {
            rows[cursorRow].cells[column + 1] = TerminalCell()
        } else if existing.width == 0, column > 0 {
            rows[cursorRow].cells[column - 1] = TerminalCell()
        }
        rows[cursorRow].cells[column] = TerminalCell(style: style)
    }

    private mutating func lineFeed() {
        joinNext = false
        regionalIndicator = false
        if cursorRow == origin + scrollBottom {
            if scrollTop == 0 && scrollBottom == height - 1 && !isAlternateScreen {
                origin += 1
                cursorRow += 1
                ensureRow(cursorRow)
            } else { scrollRegion(up: true) }
        } else {
            cursorRow = min(cursorRow + 1, origin + height - 1)
            ensureRow(cursorRow)
        }
    }

    private mutating func reverseIndex() {
        if cursorRow == origin + scrollTop { scrollRegion(up: false) }
        else { cursorRow = max(origin, cursorRow - 1) }
    }

    private mutating func scrollRegion(up: Bool) {
        let start = origin + scrollTop
        let end = origin + scrollBottom
        ensureRow(end)
        if up { rows.remove(at: start); rows.insert(TerminalRow(), at: end) }
        else { rows.remove(at: end); rows.insert(TerminalRow(), at: start) }
    }

    private mutating func restoreCursor() {
        cursorRow = max(origin, min(savedCursor.row, origin + height - 1))
        cursorColumn = max(0, min(savedCursor.column, columns - 1))
        ensureRow(cursorRow)
    }

    private mutating func executeCSI(_ command: Character) {
        let privateMode = parameters.hasPrefix("?")
        let values = parameters.trimmingCharacters(in: CharacterSet(charactersIn: "? >"))
            .split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let count = max(1, values.first ?? 1)
        func parameter(_ index: Int, fallback: Int = 1) -> Int {
            guard values.indices.contains(index), values[index] > 0 else { return fallback }
            return values[index]
        }
        switch command {
        case "m": setStyle(values)
        case "A": cursorRow = max(origin, cursorRow - count)
        case "B": cursorRow = min(origin + height - 1, cursorRow + count)
        case "C": cursorColumn = min(columns - 1, cursorColumn + count)
        case "D": cursorColumn = max(0, cursorColumn - count)
        case "E": cursorRow = min(origin + height - 1, cursorRow + count); cursorColumn = 0
        case "F": cursorRow = max(origin, cursorRow - count); cursorColumn = 0
        case "G", "`": cursorColumn = min(columns - 1, parameter(0) - 1)
        case "d": cursorRow = origin + min(height - 1, parameter(0) - 1)
        case "H", "f":
            cursorRow = origin + min(height - 1, parameter(0) - 1)
            cursorColumn = min(columns - 1, parameter(1) - 1)
        case "s": savedCursor = (cursorRow, cursorColumn)
        case "u": restoreCursor()
        case "K": eraseLine(values.first ?? 0)
        case "J": eraseDisplay(values.first ?? 0)
        case "r":
            let top = parameter(0) - 1
            let bottom = parameter(1, fallback: height) - 1
            if top >= 0 && bottom < height && top < bottom {
                scrollTop = top; scrollBottom = bottom; cursorRow = origin; cursorColumn = 0
            }
        case "S", "T": for _ in 0..<min(count, height) { scrollRegion(up: command == "S") }
        case "L", "M":
            ensureRow(origin + scrollBottom)
            if cursorRow >= origin + scrollTop && cursorRow <= origin + scrollBottom {
                for _ in 0..<min(count, scrollBottom + origin - cursorRow + 1) {
                    if command == "L" { rows.remove(at: origin + scrollBottom); rows.insert(TerminalRow(), at: cursorRow) }
                    else { rows.remove(at: cursorRow); rows.insert(TerminalRow(), at: origin + scrollBottom) }
                }
            }
        case "X":
            ensureRow(cursorRow); ensureCells(columns)
            for column in min(cursorColumn, columns - 1)..<min(columns, cursorColumn + count) { eraseCell(column) }
        case "P", "@":
            ensureRow(cursorRow); ensureCells(columns)
            let start = min(cursorColumn, columns - 1)
            let amount = min(count, columns - start)
            for _ in 0..<amount {
                if command == "P" { rows[cursorRow].cells.remove(at: start); rows[cursorRow].cells.append(TerminalCell()) }
                else { rows[cursorRow].cells.insert(TerminalCell(), at: start); rows[cursorRow].cells.removeLast() }
            }
            repairWideCells()
        case "h", "l":
            guard privateMode else { break }
            for mode in values {
                if mode == 25 { cursorVisible = command == "h" }
                if mode == 1049 || mode == 47 { alternateScreen(command == "h") }
            }
        default: break
        }
        ensureRow(cursorRow)
    }

    private mutating func repairWideCells() {
        for index in rows[cursorRow].cells.indices {
            let cell = rows[cursorRow].cells[index]
            if cell.width == 0 && (index == 0 || rows[cursorRow].cells[index - 1].width != 2) {
                rows[cursorRow].cells[index] = TerminalCell()
            }
            if cell.width == 2 && (index + 1 >= rows[cursorRow].cells.count || rows[cursorRow].cells[index + 1].width != 0) {
                rows[cursorRow].cells[index] = TerminalCell()
            }
        }
    }

    private mutating func eraseLine(_ mode: Int) {
        ensureRow(cursorRow); ensureCells(columns)
        let column = min(cursorColumn, columns - 1)
        let range = mode == 1 ? 0..<(column + 1) : (mode == 2 ? 0..<columns : column..<columns)
        for index in range { eraseCell(index) }
    }

    private mutating func eraseDisplay(_ mode: Int) {
        if mode == 3 {
            if origin > 0 { rows.removeFirst(origin); cursorRow -= origin; origin = 0 }
            return
        }
        if mode == 2 {
            for index in origin..<max(origin + height, rows.count) {
                ensureRow(index); rows[index] = TerminalRow()
            }
        } else if mode == 1 {
            for index in origin..<cursorRow { rows[index] = TerminalRow() }
            eraseLine(1)
        } else {
            eraseLine(0)
            if cursorRow + 1 < rows.count {
                for index in (cursorRow + 1)..<rows.count { rows[index] = TerminalRow() }
            }
        }
    }

    private mutating func alternateScreen(_ enabled: Bool) {
        guard enabled != isAlternateScreen else { return }
        if enabled {
            savedScreen = SavedScreen(rows: rows, origin: origin, row: cursorRow, column: cursorColumn, style: style)
            rows = [TerminalRow()]; origin = 0; cursorRow = 0; cursorColumn = 0
        } else if let saved = savedScreen {
            rows = saved.rows; origin = saved.origin; cursorRow = saved.row; cursorColumn = saved.column; style = saved.style
            savedScreen = nil
        }
        scrollTop = 0; scrollBottom = height - 1; isAlternateScreen = enabled
    }

    private mutating func setStyle(_ values: [Int]) {
        var index = 0
        while index < values.count {
            let value = values[index]
            switch value {
            case 0: style = CellStyle()
            case 1: style.bold = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: style.bold = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .indexed(value - 30)
            case 40...47: style.background = .indexed(value - 40)
            case 90...97: style.foreground = .indexed(value - 90 + 8)
            case 100...107: style.background = .indexed(value - 100 + 8)
            case 39: style.foreground = nil
            case 49: style.background = nil
            case 38, 48:
                var color: TerminalColor?
                if values.indices.contains(index + 2), values[index + 1] == 5 {
                    color = .indexed(max(0, min(255, values[index + 2]))); index += 2
                } else if values.indices.contains(index + 4), values[index + 1] == 2 {
                    color = .rgb(values[index + 2], values[index + 3], values[index + 4]); index += 4
                }
                if value == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            index += 1
        }
    }

    private mutating func trimScrollback() {
        let excess = rows.count - (isAlternateScreen ? height : scrollbackLimit + height)
        if excess > 0 {
            rows.removeFirst(excess)
            cursorRow = max(0, cursorRow - excess)
            origin = max(0, origin - excess)
            savedCursor.row = max(0, savedCursor.row - excess)
        }
    }
}
