import AppKit

// MARK: - Mode

enum VimMode: Equatable {
    case normal
    case insert
    case visual(anchor: Int, cursor: Int, linewise: Bool)
    case command(String)

    var label: String {
        switch self {
        case .normal:                         return "NORMAL"
        case .insert:                         return "INSERT"
        case .visual(_, _, let lw):           return lw ? "V-LINE" : "VISUAL"
        case .command(let buf):               return ":\(buf)"
        }
    }
}

// MARK: - VimTextView

final class VimTextView: NSTextView {

    var vimEnabled: Bool = false {
        didSet {
            if !vimEnabled { mode = .insert }
            updateCursorAppearance()
        }
    }
    var onModeChange: ((String) -> Void)?
    var onCommand: ((String) -> Void)?

    func resetToNormal() {
        pending = .none
        mode = .normal
    }

    private(set) var mode: VimMode = .normal {
        didSet {
            guard mode != oldValue else { return }
            onModeChange?(mode.label)
            updateCursorAppearance()
            needsDisplay = true
        }
    }

    private func updateCursorAppearance() {
        switch mode {
        case .normal, .command:
            insertionPointColor = vimEnabled ? .clear : .labelColor
        case .insert, .visual:
            insertionPointColor = .labelColor
        }
    }

    private enum Pending {
        case none
        case twoKey(Character)       // g, >, <  waiting for second char
        case operatorKey(Character)  // d, c, y  waiting for motion
        case replace                 // r  waiting for replacement char
    }
    private var pending: Pending = .none
    private var yankBuffer: String = ""
    private var yankLinewise: Bool = false

    // MARK: - Block cursor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockCursorIfNeeded()
    }

    private func drawBlockCursorIfNeeded() {
        guard vimEnabled, case .normal = mode else { return }
        guard window?.firstResponder === self else { return }

        let pos = selectedRange().location
        let str = string as NSString
        guard pos < str.length, str.character(at: pos) != 10 else { return }
        guard let lm = layoutManager, let tc = textContainer else { return }

        let gr = lm.glyphRange(forCharacterRange: NSRange(location: pos, length: 1),
                               actualCharacterRange: nil)
        guard gr.length > 0 else { return }

        var r = lm.boundingRect(forGlyphRange: gr, in: tc)
        r.origin.x += textContainerOrigin.x
        r.origin.y += textContainerOrigin.y

        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        r.fill()
    }

    // MARK: - Key dispatch

    override func keyDown(with event: NSEvent) {
        guard vimEnabled else { super.keyDown(with: event); return }
        switch mode {
        case .insert:
            if event.keyCode == 53 { enterNormal() } else { super.keyDown(with: event) }
        case .normal:
            handleNormal(event)
        case .visual(let a, let c, let lw):
            handleVisual(event, anchor: a, cursor: c, linewise: lw)
        case .command(let buf):
            handleCommand(event, buffer: buf)
        }
    }

    // MARK: - Command-line mode

    private func handleCommand(_ event: NSEvent, buffer: String) {
        let keyCode = event.keyCode

        // Escape → cancel
        if keyCode == 53 { mode = .normal; return }

        // Enter (main or numpad) → execute
        if keyCode == 36 || keyCode == 76 {
            let cmd = buffer
            mode = .normal
            onCommand?(cmd)
            return
        }

        // Backspace
        if keyCode == 51 {
            mode = buffer.isEmpty ? .normal : .command(String(buffer.dropLast()))
            return
        }

        // Printable chars only (no ⌘/⌃/⌥)
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty || mods == .shift, let chars = event.characters, !chars.isEmpty {
            mode = .command(buffer + chars)
        }
    }

    // MARK: - Normal mode

    private func handleNormal(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control])

        // ⌃R = redo
        if mods == .control {
            if event.charactersIgnoringModifiers?.lowercased() == "r" { undoManager?.redo() }
            pending = .none; return
        }
        // Pass ⌘/⌥ shortcuts through unchanged
        if mods.contains(.command) || mods.contains(.option) {
            super.keyDown(with: event); pending = .none; return
        }

        guard let char = event.characters?.first, mods.isEmpty || mods == .shift else { return }

        // Resolve pending state
        switch pending {
        case .twoKey(let first):
            pending = .none
            switch (first, char) {
            case ("g", "g"): moveToBeginningOfDocument(nil)
            case (">", ">"): indentLines(in: currentLineRange(), dedent: false)
            case ("<", "<"): indentLines(in: currentLineRange(), dedent: true)
            default: break
            }
            return

        case .operatorKey(let op):
            pending = .none
            if char == op {
                // dd, yy, cc → line operation
                switch op {
                case "d": deleteCurrentLine()
                case "y": yankCurrentLine()
                case "c": deleteCurrentLine(); mode = .insert
                default: break
                }
            } else {
                operatorMotion(op: op, motion: char)
            }
            return

        case .replace:
            pending = .none
            replaceChar(with: char)
            return

        case .none: break
        }

        // Normal dispatch
        switch char {
        // Navigation
        case "h": moveLeft(nil)
        case "j": moveDown(nil)
        case "k": moveUp(nil)
        case "l": moveRight(nil)
        case "w": moveWordForward(nil)
        case "b": moveWordBackward(nil)
        case "e": moveWordForward(nil)
        case "0": moveToBeginningOfLine(nil)
        case "$": moveToEndOfLine(nil)
        case "G": moveToEndOfDocument(nil)
        case "^": moveToFirstNonBlank()
        case "g", ">", "<": pending = .twoKey(char)
        // Enter insert
        case "i": mode = .insert
        case "a": moveForwardIfNotLineEnd(); mode = .insert
        case "A": moveToEndOfLine(nil);      mode = .insert
        case "I": moveToFirstNonBlank();      mode = .insert
        case "o": openLineBelow();            mode = .insert
        case "O": openLineAbove();            mode = .insert
        case "s":
            undoManager?.beginUndoGrouping()
            deleteCharAtCursor()
            undoManager?.endUndoGrouping()
            mode = .insert
        // Operators
        case "d", "c", "y": pending = .operatorKey(char)
        // Compound shorthands
        case "D": operatorMotion(op: "d", motion: "$")
        case "C": operatorMotion(op: "c", motion: "$")
        case "Y": yankCurrentLine()
        // Edit
        case "x": deleteCharAtCursor()
        case "X": deleteCharBefore()
        case "r": pending = .replace
        case "~": toggleCaseAtCursor()
        case "p": pasteBuffer(after: true)
        case "P": pasteBuffer(after: false)
        case "u": undoManager?.undo()
        // Visual
        case "v":
            let pos = selectedRange().location
            mode = .visual(anchor: pos, cursor: pos, linewise: false)
            setSelectedRange(NSRange(location: pos, length: 1))
        case "V":
            let pos = selectedRange().location
            mode = .visual(anchor: pos, cursor: pos, linewise: true)
            updateVisualSelection(anchor: pos, cursor: pos, linewise: true)
        // Command-line
        case ":":
            mode = .command("")
        default: break
        }
    }

    // MARK: - Visual mode

    private func handleVisual(_ event: NSEvent, anchor: Int, cursor: Int, linewise: Bool) {
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        if mods.contains(.command) || mods.contains(.option) { super.keyDown(with: event); return }

        if event.keyCode == 53 { // Escape
            setSelectedRange(NSRange(location: min(anchor, cursor), length: 0))
            mode = .normal; return
        }

        guard let char = event.characters?.first, mods.isEmpty || mods == .shift else { return }

        switch char {
        // Navigation: move cursor end of selection
        case "h", "j", "k", "l", "w", "b", "e", "0", "$", "^", "G":
            setSelectedRange(NSRange(location: cursor, length: 0))
            applyMotion(char)
            let newCursor = selectedRange().location
            mode = .visual(anchor: anchor, cursor: newCursor, linewise: linewise)
            updateVisualSelection(anchor: anchor, cursor: newCursor, linewise: linewise)

        // Operations on selection
        case "d", "x":
            visualDelete(anchor: anchor, cursor: cursor, linewise: linewise, enterInsert: false)
        case "c":
            visualDelete(anchor: anchor, cursor: cursor, linewise: linewise, enterInsert: true)
        case "y":
            yankBuffer = (string as NSString).substring(with: visualRange(anchor: anchor, cursor: cursor, linewise: linewise))
            yankLinewise = linewise
            setSelectedRange(NSRange(location: min(anchor, cursor), length: 0))
            mode = .normal
        case "p":
            let range = visualRange(anchor: anchor, cursor: cursor, linewise: linewise)
            insertText(yankBuffer, replacementRange: range)
            mode = .normal
        case "~":
            let range = visualRange(anchor: anchor, cursor: cursor, linewise: linewise)
            let toggled = toggleCaseString((string as NSString).substring(with: range))
            insertText(toggled, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: 0))
            mode = .normal
        case ">":
            indentLines(in: visualRange(anchor: anchor, cursor: cursor, linewise: true), dedent: false)
            mode = .normal
        case "<":
            indentLines(in: visualRange(anchor: anchor, cursor: cursor, linewise: true), dedent: true)
            mode = .normal
        // Switch between char/line visual
        case "v":
            mode = .visual(anchor: anchor, cursor: cursor, linewise: false)
            updateVisualSelection(anchor: anchor, cursor: cursor, linewise: false)
        case "V":
            mode = .visual(anchor: anchor, cursor: cursor, linewise: true)
            updateVisualSelection(anchor: anchor, cursor: cursor, linewise: true)
        default: break
        }
    }

    // MARK: - Operator + motion

    private func operatorMotion(op: Character, motion: Character) {
        let startPos = selectedRange().location
        applyMotion(motion)
        let endPos = selectedRange().location

        let lo = min(startPos, endPos)
        let hi = max(startPos, endPos)
        let str = string as NSString

        // For forward motions, range is [startPos, endPos); for backward [endPos, startPos)
        let range = NSRange(location: lo, length: hi - lo)
        guard range.length > 0 else { setSelectedRange(NSRange(location: startPos, length: 0)); return }

        yankBuffer = str.substring(with: range)
        yankLinewise = false

        switch op {
        case "d":
            insertText("", replacementRange: range)
        case "c":
            insertText("", replacementRange: range)
            mode = .insert
        case "y":
            setSelectedRange(NSRange(location: startPos, length: 0))
        default: break
        }
    }

    private func applyMotion(_ char: Character) {
        switch char {
        case "h": moveLeft(nil)
        case "j": moveDown(nil)
        case "k": moveUp(nil)
        case "l": moveRight(nil)
        case "w": moveWordForward(nil)
        case "b": moveWordBackward(nil)
        case "e": moveWordForward(nil)
        case "0": moveToBeginningOfLine(nil)
        case "$": moveToEndOfLine(nil)
        case "^": moveToFirstNonBlank()
        case "G": moveToEndOfDocument(nil)
        default: break
        }
    }

    // MARK: - Visual helpers

    private func visualRange(anchor: Int, cursor: Int, linewise: Bool) -> NSRange {
        let str = string as NSString
        let len = str.length
        if linewise {
            let a = min(anchor, cursor, len > 0 ? len - 1 : 0)
            let b = min(max(anchor, cursor), len > 0 ? len - 1 : 0)
            let aRange = str.lineRange(for: NSRange(location: a, length: 0))
            let bRange = str.lineRange(for: NSRange(location: b, length: 0))
            let start = aRange.location
            let end   = bRange.location + bRange.length
            return NSRange(location: start, length: max(0, end - start))
        } else {
            let start = min(anchor, cursor)
            let end   = min(max(anchor, cursor) + 1, len)
            return NSRange(location: start, length: max(0, end - start))
        }
    }

    private func updateVisualSelection(anchor: Int, cursor: Int, linewise: Bool) {
        setSelectedRange(visualRange(anchor: anchor, cursor: cursor, linewise: linewise))
    }

    private func visualDelete(anchor: Int, cursor: Int, linewise: Bool, enterInsert: Bool) {
        let range = visualRange(anchor: anchor, cursor: cursor, linewise: linewise)
        yankBuffer = (string as NSString).substring(with: range)
        yankLinewise = linewise
        insertText("", replacementRange: range)
        mode = enterInsert ? .insert : .normal
    }

    // MARK: - Motion helpers

    private func moveToFirstNonBlank() {
        moveToBeginningOfLine(nil)
        let str = string as NSString
        var loc = selectedRange().location
        let len = str.length
        while loc < len {
            let c = str.character(at: loc)
            if c == 10 || (c != 32 && c != 9) { break }
            loc += 1
        }
        setSelectedRange(NSRange(location: loc, length: 0))
    }

    private func moveForwardIfNotLineEnd() {
        let range = selectedRange()
        let str = string as NSString
        if range.location < str.length, str.character(at: range.location) != 10 {
            moveRight(nil)
        }
    }

    private func currentLineRange() -> NSRange {
        let str = string as NSString
        return str.lineRange(for: NSRange(location: selectedRange().location, length: 0))
    }

    private func openLineBelow() {
        moveToEndOfLine(nil)
        let pos = selectedRange().location
        insertText("\n", replacementRange: NSRange(location: pos, length: 0))
    }

    private func openLineAbove() {
        moveToBeginningOfLine(nil)
        let pos = selectedRange().location
        insertText("\n", replacementRange: NSRange(location: pos, length: 0))
        setSelectedRange(NSRange(location: pos, length: 0))
    }

    // MARK: - Edit helpers

    private func enterNormal() {
        let range = selectedRange()
        if range.location > 0 {
            let str = string as NSString
            if str.character(at: range.location - 1) != 10 {
                setSelectedRange(NSRange(location: range.location - 1, length: 0))
            }
        }
        mode = .normal
    }

    private func deleteCharAtCursor() {
        let range = selectedRange()
        let str = string as NSString
        guard range.location < str.length, str.character(at: range.location) != 10 else { return }
        let r = NSRange(location: range.location, length: 1)
        yankBuffer = str.substring(with: r); yankLinewise = false
        insertText("", replacementRange: r)
    }

    private func deleteCharBefore() {
        let range = selectedRange()
        guard range.location > 0 else { return }
        let str = string as NSString
        guard str.character(at: range.location - 1) != 10 else { return }
        let r = NSRange(location: range.location - 1, length: 1)
        yankBuffer = str.substring(with: r); yankLinewise = false
        insertText("", replacementRange: r)
    }

    private func deleteCurrentLine() {
        let str = string as NSString
        let lineRange = str.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        yankBuffer = str.substring(with: lineRange); yankLinewise = true
        insertText("", replacementRange: lineRange)
    }

    private func yankCurrentLine() {
        let str = string as NSString
        let lineRange = str.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        yankBuffer = str.substring(with: lineRange); yankLinewise = true
    }

    private func replaceChar(with char: Character) {
        let range = selectedRange()
        let str = string as NSString
        guard range.location < str.length, str.character(at: range.location) != 10 else { return }
        insertText(String(char), replacementRange: NSRange(location: range.location, length: 1))
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    private func toggleCaseAtCursor() {
        let range = selectedRange()
        let str = string as NSString
        guard range.location < str.length, str.character(at: range.location) != 10 else { return }
        let r = NSRange(location: range.location, length: 1)
        let ch = str.substring(with: r)
        insertText(toggleCaseString(ch), replacementRange: r)
        let next = min(range.location + 1, (string as NSString).length)
        setSelectedRange(NSRange(location: next, length: 0))
    }

    private func toggleCaseString(_ s: String) -> String {
        String(s.map { c in
            c.isUppercase ? Character(c.lowercased()) : Character(c.uppercased())
        })
    }

    private func pasteBuffer(after: Bool) {
        guard !yankBuffer.isEmpty else { return }
        let range = selectedRange()
        let str = string as NSString
        if yankLinewise {
            let lineRange = str.lineRange(for: range)
            if after {
                let pos = min(lineRange.location + lineRange.length, str.length)
                insertText(yankBuffer, replacementRange: NSRange(location: pos, length: 0))
                setSelectedRange(NSRange(location: pos, length: 0))
            } else {
                insertText(yankBuffer, replacementRange: NSRange(location: lineRange.location, length: 0))
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
            }
        } else {
            let pos = after ? min(range.location + 1, str.length) : range.location
            insertText(yankBuffer, replacementRange: NSRange(location: pos, length: 0))
        }
    }

    private func indentLines(in range: NSRange, dedent: Bool) {
        let str = string as NSString
        guard range.length > 0 else { return }
        let text = str.substring(with: range)
        var lines = text.components(separatedBy: "\n")
        // Don't indent the trailing empty element from a trailing newline
        let trailingNewline = text.hasSuffix("\n")
        let count = trailingNewline ? lines.count - 1 : lines.count
        for i in 0..<count {
            if dedent {
                if lines[i].hasPrefix("\t")    { lines[i] = String(lines[i].dropFirst()) }
                else if lines[i].hasPrefix("    ") { lines[i] = String(lines[i].dropFirst(4)) }
            } else {
                lines[i] = "    " + lines[i]
            }
        }
        insertText(lines.joined(separator: "\n"), replacementRange: range)
    }
}
