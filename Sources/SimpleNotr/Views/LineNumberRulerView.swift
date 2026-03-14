import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var observers: [Any] = []

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
        registerObservers()
    }

    required init(coder: NSCoder) { fatalError() }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Setup

    private func registerObservers() {
        let nc = NotificationCenter.default
        if let ts = textView?.textStorage {
            observers.append(nc.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: ts, queue: .main) { [weak self] _ in
                    self?.updateThickness()
                    self?.needsDisplay = true
            })
        }
        if let cv = scrollView?.contentView {
            cv.postsBoundsChangedNotifications = true
            observers.append(nc.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: cv, queue: .main) { [weak self] _ in
                    self?.needsDisplay = true
            })
        }
        if let tv = textView {
            observers.append(nc.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: tv, queue: .main) { [weak self] _ in
                    self?.needsDisplay = true
            })
        }
    }

    func updateThickness() {
        guard let tv = textView else { return }
        let lineCount = max(1, tv.string.components(separatedBy: "\n").count)
        let digits = max(2, "\(lineCount)".count)
        let f = Self.numFont(for: tv)
        let w = ceil((String(repeating: "9", count: digits) as NSString)
            .size(withAttributes: [.font: f]).width) + 16
        if abs(ruleThickness - w) > 0.5 { ruleThickness = w }
    }

    private static func numFont(for tv: NSTextView) -> NSFont {
        .monospacedSystemFont(ofSize: max(9, (tv.font?.pointSize ?? 13) - 1), weight: .regular)
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }

        // Background + right border
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let text       = tv.string as NSString
        let cursorPos  = tv.selectedRange().location
        let currentLine: Int = {
            var n = 1
            let end = min(cursorPos, text.length)
            for i in 0..<end { if text.character(at: i) == 10 { n += 1 } }
            return n
        }()

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.numFont(for: tv),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let currentAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.numFont(for: tv),
            .foregroundColor: NSColor.labelColor
        ]

        // Empty document: just show "1"
        if text.length == 0 {
            let h = lm.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 13))
            draw(lineNumber: 1, lineRect: NSRect(x: 0, y: 0, width: 0, height: h),
                 in: tv, attrs: currentAttrs, isCurrent: true)
            return
        }

        let visibleGlyphRange = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        let firstVisibleChar = lm.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil).location

        // Count newlines before the first visible character to find starting line number
        var lineNumber = 1
        for i in 0..<firstVisibleChar {
            if text.character(at: i) == 10 { lineNumber += 1 }
        }

        var lastLineRect = NSRect.zero

        lm.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { lineRect, _, _, glyphRange, _ in
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isParagraphStart = charRange.location == 0 ||
                text.character(at: charRange.location - 1) == 10

            if isParagraphStart {
                let isCurrent = lineNumber == currentLine
                self.draw(lineNumber: lineNumber, lineRect: lineRect, in: tv,
                          attrs: isCurrent ? currentAttrs : baseAttrs, isCurrent: isCurrent)
                lineNumber += 1
            }
            lastLineRect = lineRect
        }

        // Extra line after a trailing newline
        if text.character(at: text.length - 1) == 10 {
            let extraRect = NSRect(x: 0, y: lastLineRect.maxY,
                                   width: 0, height: lastLineRect.height)
            let isCurrent = lineNumber == currentLine
            draw(lineNumber: lineNumber, lineRect: extraRect, in: tv,
                 attrs: isCurrent ? currentAttrs : baseAttrs, isCurrent: isCurrent)
        }
    }

    private func draw(lineNumber n: Int, lineRect: NSRect,
                      in tv: NSTextView, attrs: [NSAttributedString.Key: Any],
                      isCurrent: Bool) {
        let label     = "\(n)" as NSString
        let labelSize = label.size(withAttributes: attrs)

        // lineRect is in text-container space; shift by inset to get text-view space,
        // then convert to ruler-view space.
        let lineY  = lineRect.minY + tv.textContainerInset.height
        let rulerY = convert(NSPoint(x: 0, y: lineY), from: tv).y

        if isCurrent {
            let highlightRect = NSRect(x: 0, y: rulerY, width: bounds.width - 1, height: lineRect.height)
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            highlightRect.fill()
        }

        label.draw(at: NSPoint(
            x: bounds.maxX - labelSize.width - 8,
            y: rulerY + (lineRect.height - labelSize.height) / 2
        ), withAttributes: attrs)
    }
}
