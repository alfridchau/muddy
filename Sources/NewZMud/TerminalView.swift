import AppKit
import SwiftUI

struct TerminalView: NSViewRepresentable {
    var buffer: TerminalBuffer
    var fontSize: Double
    var theme: TerminalTheme
    var search: String
    @Binding var following: Bool
    @Binding var newOutput: Int
    var onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let canvas = TerminalCanvas()
        scroll.documentView = canvas
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        context.coordinator.scroll = scroll
        context.coordinator.canvas = canvas
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in coordinator?.didScroll() }
        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in coordinator?.layout() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.canvas?.buffer.outputRevision != buffer.outputRevision
        let canvas = coordinator.canvas
        let contentChanged = canvas?.buffer.revision != buffer.revision
        let fontChanged = canvas?.fontSize != fontSize
        let themeChanged = canvas?.theme != theme
        let filterChanged = canvas?.filter != search
        let initialRefresh = !(canvas?.hasRefreshed ?? false)
        let resumedFollowing = !coordinator.lastFollowing && following
        coordinator.parent = self
        coordinator.lastFollowing = following
        if contentChanged { canvas?.buffer = buffer }
        if fontChanged { canvas?.fontSize = fontSize }
        if themeChanged { canvas?.theme = theme }
        if filterChanged { canvas?.filter = search }
        if contentChanged || filterChanged || initialRefresh {
            canvas?.refreshRows(updateAccessibility: contentChanged || initialRefresh)
        }
        if contentChanged || fontChanged || themeChanged || filterChanged || initialRefresh {
            coordinator.layout()
        } else if resumedFollowing {
            coordinator.scrollToBottom()
        }
        if changed && !following {
            DispatchQueue.main.async { coordinator.parent.newOutput += 1 }
        }
    }

    final class Coordinator {
        var parent: TerminalView
        weak var scroll: NSScrollView?
        weak var canvas: TerminalCanvas?
        var boundsObserver: NSObjectProtocol?
        var frameObserver: NSObjectProtocol?
        var programmatic = false
        var lastFollowing: Bool
        var lastColumns = 0
        var lastRows = 0
        var resizeWork: DispatchWorkItem?

        init(_ parent: TerminalView) { self.parent = parent; lastFollowing = parent.following }
        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            resizeWork?.cancel()
        }

        func didScroll() {
            guard !programmatic, let scroll, let canvas else { return }
            let remaining = canvas.frame.height - scroll.contentView.bounds.maxY
            let atBottom = remaining < canvas.lineHeight * 1.5
            guard parent.following != atBottom || (atBottom && parent.newOutput > 0) else { return }
            DispatchQueue.main.async {
                if self.parent.following != atBottom { self.parent.following = atBottom }
                if atBottom && self.parent.newOutput > 0 { self.parent.newOutput = 0 }
            }
        }

        func scrollToBottom() {
            guard let scroll, let canvas else { return }
            let visible = scroll.contentView.bounds
            programmatic = true
            scroll.contentView.scroll(to: NSPoint(x: visible.minX, y: max(0, canvas.frame.height - visible.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            programmatic = false
        }

        func layout() {
            guard let scroll, let canvas else { return }
            let previous = programmatic
            programmatic = true
            defer { programmatic = previous }
            let visible = scroll.contentView.bounds
            guard visible.width > 40, visible.height > 32 else { return }
            let columns = max(20, Int((visible.width - 40) / canvas.cellWidth))
            let rows = max(5, Int((visible.height - 32) / canvas.lineHeight))
            canvas.setFrameSize(NSSize(
                width: max(visible.width, CGFloat(canvas.longestVisibleRow) * canvas.cellWidth + 40),
                height: max(visible.height, CGFloat(canvas.visibleRows.count) * canvas.lineHeight + 32)
            ))
            if parent.following {
                scroll.contentView.scroll(to: NSPoint(x: visible.minX, y: max(0, canvas.frame.height - visible.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                if parent.newOutput > 0 { DispatchQueue.main.async { self.parent.newOutput = 0 } }
            }
            canvas.needsDisplay = true
            if columns != lastColumns || rows != lastRows {
                lastColumns = columns; lastRows = rows
                resizeWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.parent.onResize(columns, rows) }
                resizeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }
    }
}

final class TerminalCanvas: NSView {
    var buffer = TerminalBuffer()
    var fontSize: Double = 14
    var theme: TerminalTheme = .midnight { didSet { needsDisplay = true } }
    var filter = ""
    var visibleRows: [Int] = []
    var longestVisibleRow = 0
    var hasRefreshed = false
    private var selectionStart: (row: Int, column: Int)?
    private var selectionEnd: (row: Int, column: Int)?
    private let padding: CGFloat = 20

    override var isFlipped: Bool { true }
    var font: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var cellWidth: CGFloat { ("M" as NSString).size(withAttributes: [.font: font]).width }
    var lineHeight: CGFloat { ceil(fontSize * 1.65) }
    private var themeBackground: NSColor {
        switch theme {
        case .midnight: NSColor(Palette.canvas)
        case .paper: NSColor(calibratedWhite: 0.94, alpha: 1)
        case .amber: NSColor(srgbRed: 0.10, green: 0.07, blue: 0.035, alpha: 1)
        }
    }
    private var themeForeground: NSColor {
        switch theme {
        case .midnight: NSColor(Palette.ink)
        case .paper: NSColor(calibratedWhite: 0.12, alpha: 1)
        case .amber: NSColor(srgbRed: 0.94, green: 0.72, blue: 0.36, alpha: 1)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Game terminal")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshRows(updateAccessibility: Bool) {
        visibleRows = buffer.rows.indices.filter { filter.isEmpty || buffer.rows[$0].text.localizedCaseInsensitiveContains(filter) }
        longestVisibleRow = visibleRows.map { buffer.rows[$0].cells.count }.max() ?? 0
        hasRefreshed = true
        if updateAccessibility {
            setAccessibilityValue(visibleRows.map { buffer.rows[$0].text }.joined(separator: "\n"))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        themeBackground.setFill()
        dirtyRect.fill()
        guard !visibleRows.isEmpty else { return }
        let first = max(0, Int((dirtyRect.minY - 16) / lineHeight))
        let last = min(visibleRows.count - 1, max(first, Int((dirtyRect.maxY - 16) / lineHeight)))
        guard first <= last else { return }
        for displayed in first...last {
            let row = buffer.rows[visibleRows[displayed]]
            let rowRect = NSRect(x: 0, y: 16 + CGFloat(displayed) * lineHeight, width: bounds.width, height: lineHeight)
            guard dirtyRect.intersects(rowRect) else { continue }
            var column = 0
            while column < row.cells.count {
                if row.cells[column].width == 0 { column += 1; continue }
                let start = column
                let style = row.cells[column].style
                column += 1
                while column < row.cells.count {
                    if row.cells[column].width > 0 && row.cells[column].style != style { break }
                    column += 1
                }
                drawStyleRun(row, displayedRow: displayed, start: start, end: column, style: style)
            }
        }
        if buffer.cursorVisible, filter.isEmpty, let row = visibleRows.firstIndex(of: buffer.cursorRow) {
            NSColor(Palette.jade).withAlphaComponent(0.55).setFill()
            NSRect(x: padding + CGFloat(min(buffer.columns - 1, buffer.cursorColumn)) * cellWidth,
                   y: 16 + CGFloat(row + 1) * lineHeight - 2, width: cellWidth, height: 1).fill()
        }
    }

    private func drawStyleRun(_ row: TerminalRow, displayedRow: Int, start: Int, end: Int, style: CellStyle) {
        let rect = NSRect(x: padding + CGFloat(start) * cellWidth,
                          y: 16 + CGFloat(displayedRow) * lineHeight,
                          width: CGFloat(end - start) * cellWidth, height: lineHeight)
        var foreground = Self.color(style.foreground, fallback: themeForeground, bright: style.bold)
        var background = Self.color(style.background, fallback: themeBackground)
        if style.inverse { swap(&foreground, &background) }
        NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
        background.setFill(); rect.fill()
        NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
        let base = NSFont.monospacedSystemFont(ofSize: fontSize, weight: style.bold ? .bold : .regular)
        let renderedFont = style.italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
        for column in start..<end where row.cells[column].width > 0 {
            let cell = row.cells[column]
            let cellRect = NSRect(x: padding + CGFloat(column) * cellWidth, y: rect.minY,
                                  width: CGFloat(cell.width) * cellWidth, height: lineHeight)
            if isSelected(displayedRow, column) {
                NSColor(Palette.jade).withAlphaComponent(0.27).setFill()
                cellRect.fill()
            }
            (cell.text as NSString).draw(at: NSPoint(x: cellRect.minX, y: cellRect.minY + (lineHeight - fontSize) / 2 - 2),
                                         withAttributes: [.font: renderedFont, .foregroundColor: foreground])
        }
        if style.underline {
            foreground.setFill()
            NSRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 1).fill()
        }
    }

    private static func color(_ color: TerminalColor?, fallback: NSColor, bright: Bool = false) -> NSColor {
        guard let color else { return fallback }
        switch color {
        case .rgb(let red, let green, let blue):
            return NSColor(srgbRed: CGFloat(max(0, min(255, red))) / 255,
                           green: CGFloat(max(0, min(255, green))) / 255,
                           blue: CGFloat(max(0, min(255, blue))) / 255, alpha: 1)
        case .indexed(let code):
            let index = bright && code < 8 ? code + 8 : code
            let colors: [(Int, Int, Int)] = [
                (32, 38, 42), (210, 99, 99), (124, 187, 139), (204, 176, 111),
                (110, 153, 208), (178, 131, 196), (104, 183, 192), (205, 213, 214),
                (105, 118, 124), (246, 134, 134), (160, 220, 175), (236, 210, 148),
                (151, 189, 238), (212, 168, 230), (146, 220, 228), (245, 247, 245)
            ]
            if index < 16 {
                let rgb = colors[max(0, index)]
                return Self.color(.rgb(rgb.0, rgb.1, rgb.2), fallback: fallback)
            }
            if index >= 232 {
                let gray = 8 + min(23, index - 232) * 10
                return Self.color(.rgb(gray, gray, gray), fallback: fallback)
            }
            let value = max(0, index - 16)
            let levels = [0, 95, 135, 175, 215, 255]
            return Self.color(.rgb(levels[min(5, value / 36)], levels[(value / 6) % 6], levels[value % 6]), fallback: fallback)
        }
    }

    private func position(_ event: NSEvent) -> (row: Int, column: Int) {
        let point = convert(event.locationInWindow, from: nil)
        return (max(0, min(visibleRows.count - 1, Int((point.y - 16) / lineHeight))),
                max(0, Int((point.x - padding) / cellWidth)))
    }

    override func mouseDown(with event: NSEvent) {
        selectionStart = position(event); selectionEnd = selectionStart
        if event.clickCount == 3, let start = selectionStart, visibleRows.indices.contains(start.row) {
            selectionStart = (start.row, 0)
            selectionEnd = (start.row, buffer.rows[visibleRows[start.row]].cells.count)
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { selectionEnd = position(event); autoscroll(with: event); needsDisplay = true }

    private func isSelected(_ row: Int, _ column: Int) -> Bool {
        guard let a = selectionStart, let b = selectionEnd else { return false }
        let start = (a.row, a.column) <= (b.row, b.column) ? a : b
        let end = (a.row, a.column) <= (b.row, b.column) ? b : a
        return (row, column) >= (start.row, start.column) && (row, column) < (end.row, end.column)
    }

    @objc func copy(_ sender: Any?) {
        guard let a = selectionStart, let b = selectionEnd else { return }
        let firstRow = min(a.row, b.row)
        let lastRow = max(a.row, b.row)
        var selected: [String] = []
        for (displayed, index) in visibleRows.enumerated() where displayed >= firstRow && displayed <= lastRow {
            let row = buffer.rows[index]
            let text = row.cells.enumerated().filter { $0.element.width > 0 && isSelected(displayed, $0.offset) }.map { $0.element.text }.joined()
            selected.append(text)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selected.joined(separator: "\n"), forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        guard let index = visibleRows.last else { return }
        selectionStart = (0, 0)
        selectionEnd = (visibleRows.count - 1, buffer.rows[index].cells.count)
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        let all = menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        all.target = self
        return menu
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { copy(nil) }
        else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" { selectAll(nil) }
        else { super.keyDown(with: event) }
    }
}
