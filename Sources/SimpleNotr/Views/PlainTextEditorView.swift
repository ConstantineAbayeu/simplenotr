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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // ── Security: disable all automatic processing ──────────────────────
        textView.isAutomaticLinkDetectionEnabled    = false
        textView.isAutomaticDataDetectionEnabled    = false
        textView.isAutomaticTextReplacementEnabled  = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        // ────────────────────────────────────────────────────────────────────

        textView.isRichText  = false
        textView.allowsUndo  = true
        textView.isEditable  = true
        textView.isSelectable = true
        textView.usesFindBar  = true
        textView.font = font
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

        textView.delegate = context.coordinator
        textView.string   = text

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if the model changed externally (e.g. file switch)
        if textView.string != text {
            textView.string = text
            let safeLoc = min(restoreCursorTo, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
            textView.scrollRangeToVisible(NSRange(location: safeLoc, length: 0))
            textView.window?.makeFirstResponder(textView)
        }
        // Keep closures fresh so they always reference the current EditorView instance.
        context.coordinator.onChange = onChange
        context.coordinator.onCursorPositionChange = onCursorPositionChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onChange: onChange) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onChange: (() -> Void)?
        var onCursorPositionChange: ((Int) -> Void)?

        init(text: Binding<String>, onChange: (() -> Void)?) {
            _text = text
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text else { return }
            text = tv.string
            onChange?()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onCursorPositionChange?(tv.selectedRange().location)
        }
    }
}
