import SwiftUI
import AppKit

/// A secure, plain-text NSTextView wrapper.
/// All automatic link/data detection is disabled so URLs in .txt files
/// are never processed, highlighted, or made clickable.
struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var onChange: (() -> Void)?
    var restoreCursorTo: Int = 0
    var onCursorPositionChange: ((Int) -> Void)?
    var isVimEnabled: Bool = false
    var onVimModeChange: ((String) -> Void)?
    var onCommand: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .noBorder

        let textView = VimTextView()

        // ── Security: disable all automatic processing ──────────────────────
        textView.isAutomaticLinkDetectionEnabled      = false
        textView.isAutomaticDataDetectionEnabled      = false
        textView.isAutomaticTextReplacementEnabled    = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        // ────────────────────────────────────────────────────────────────────

        textView.isRichText   = false
        textView.allowsUndo   = true
        textView.isEditable   = true
        textView.isSelectable = true
        textView.usesFindBar  = true
        textView.font = font
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask        = [.width]
        textView.textContainer?.widthTracksTextView    = true
        textView.textContainer?.heightTracksTextView   = false

        textView.delegate   = context.coordinator
        textView.string     = text

        textView.vimEnabled   = isVimEnabled
        textView.onModeChange = onVimModeChange
        textView.onCommand    = onCommand

        scrollView.documentView = textView
        context.coordinator.trackedTextView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VimTextView else { return }

        if textView.string != text {
            textView.string = text
            let safeLoc = min(restoreCursorTo, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
            textView.scrollRangeToVisible(NSRange(location: safeLoc, length: 0))
            textView.window?.makeFirstResponder(textView)
            // Reset vim to normal mode when the file changes
            if isVimEnabled { textView.resetToNormal() }
        }

        // Keep closures and settings fresh on every update.
        context.coordinator.onChange             = onChange
        context.coordinator.onCursorPositionChange = onCursorPositionChange
        context.coordinator.trackedTextView      = textView

        textView.vimEnabled   = isVimEnabled
        textView.onModeChange = onVimModeChange
        textView.onCommand    = onCommand
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onChange: (() -> Void)?
        var onCursorPositionChange: ((Int) -> Void)?
        weak var trackedTextView: NSTextView?

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text else { return }
            text = tv.string
            onChange?()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onCursorPositionChange?(tv.selectedRange().location)
            // Redraw block cursor at new position
            if let vtv = tv as? VimTextView, vtv.vimEnabled {
                vtv.needsDisplay = true
            }
        }
    }
}
