import SwiftUI
import AppKit

// MARK: - Editor View

struct EditorView: View {
    let item: NoteItem
    @Binding var selectedItem: NoteItem?
    @Binding var cursorPositions: [URL: Int]

    @AppStorage("sn.vimModeEnabled")  private var vimModeEnabled = false
    @AppStorage("sn.fontSize")        private var fontSize: Double = 14
    @AppStorage("sn.showPreview")     private var showPreview = true
    @AppStorage("sn.previewLayout")   private var previewLayoutRaw = "sideBySide"

    @State private var vimModeLabel: String = "NORMAL"
    @State private var commandFeedback: String? = nil
    @State private var content: String = ""
    @State private var saveStatus: SaveStatus = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var fileURL: URL
    @State private var currentCursorPosition: Int = 0

    private enum SaveStatus { case saved, unsaved, saving }
    private enum PreviewLayout: String { case sideBySide, topBottom }
    private var previewLayout: PreviewLayout { PreviewLayout(rawValue: previewLayoutRaw) ?? .sideBySide }

    private var hasPreview: Bool { item.noteType == .markdown || item.noteType == .mermaid }

    init(item: NoteItem, selectedItem: Binding<NoteItem?>, cursorPositions: Binding<[URL: Int]>) {
        self.item = item
        self._selectedItem = selectedItem
        self._cursorPositions = cursorPositions
        self._fileURL = State(initialValue: item.url)
        self._currentCursorPosition = State(initialValue: cursorPositions.wrappedValue[item.url] ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if vimModeEnabled {
                Divider()
                HStack(spacing: 0) {
                    Text(statusBarText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    Spacer()
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadContent() }
        .onChange(of: item) { newItem in
            cursorPositions[fileURL] = currentCursorPosition
            flushSave()
            fileURL = newItem.url
            currentCursorPosition = cursorPositions[newItem.url] ?? 0
            vimModeLabel = "NORMAL"
            commandFeedback = nil
            loadContent()
        }
        .onDisappear { flushSave() }
        .onReceive(NotificationCenter.default.publisher(for: .saveAll)) { _ in save() }
    }

    // MARK: - Status bar

    private var statusBarText: String {
        if let fb = commandFeedback { return fb }
        if vimModeLabel.hasPrefix(":") { return vimModeLabel }
        return "-- \(vimModeLabel) --"
    }

    // MARK: - Editor content

    @ViewBuilder
    private var editorContent: some View {
        switch item.noteType {
        case .markdown:
            splitLayout {
                MarkdownPreviewView(content: content, selectedItem: $selectedItem)
                    .background(.background)
            }
        case .mermaid:
            splitLayout {
                MermaidPreviewView(content: content)
                    .background(.background)
            }
        default:
            plainTextView
        }
    }

    // MARK: - Split layout helper

    @ViewBuilder
    private func splitLayout<Preview: View>(@ViewBuilder preview: () -> Preview) -> some View {
        if showPreview && previewLayout == .topBottom {
            VSplitView {
                editorPane.frame(minHeight: 80)
                preview().frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showPreview {
            HSplitView {
                editorPane.frame(minWidth: 220)
                preview().frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            editorPane
        }
    }

    // MARK: - Shared editor pane

    private var editorPane: some View {
        PlainTextEditorView(
            text: $content,
            font: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
            onChange: scheduleAutosave,
            restoreCursorTo: currentCursorPosition,
            onCursorPositionChange: { currentCursorPosition = $0 },
            isVimEnabled: vimModeEnabled,
            onVimModeChange: { vimModeLabel = $0 },
            onCommand: handleExCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Plain text editor (TXT)

    private var plainTextView: some View {
        PlainTextEditorView(
            text: $content,
            font: .systemFont(ofSize: fontSize),
            onChange: scheduleAutosave,
            restoreCursorTo: currentCursorPosition,
            onCursorPositionChange: { currentCursorPosition = $0 },
            isVimEnabled: vimModeEnabled,
            onVimModeChange: { vimModeLabel = $0 },
            onCommand: handleExCommand
        )
    }

    // MARK: - Ex commands

    private func handleExCommand(_ raw: String) {
        let force = raw.hasSuffix("!")
        let cmd   = force ? String(raw.dropLast()) : raw

        switch cmd {
        case "w":
            save()
        case "q":
            if !force && saveStatus == .unsaved {
                showFeedback("E37: No write since last change (add ! to override)")
            } else {
                NotificationCenter.default.post(name: .closeTab, object: nil)
            }
        case "wq":
            save()
            NotificationCenter.default.post(name: .closeTab, object: nil)
        case "qa":
            if !force && saveStatus == .unsaved {
                showFeedback("E37: No write since last change (add ! to override)")
            } else {
                NSApp.terminate(nil)
            }
        case "wa":
            NotificationCenter.default.post(name: .saveAll, object: nil)
        case "wqa":
            NotificationCenter.default.post(name: .saveAll, object: nil)
            NSApp.terminate(nil)
        default:
            showFeedback("E492: Not an editor command: \(raw)")
        }
    }

    private func showFeedback(_ message: String) {
        commandFeedback = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { commandFeedback = nil }
    }

    // MARK: - File I/O

    private func loadContent() {
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
            saveStatus = .saved
        } catch {
            content = ""
        }
    }

    private func scheduleAutosave() {
        saveStatus = .unsaved
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { save() }
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard saveStatus == .unsaved else { return }
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            saveStatus = .saved
        } catch {
            saveStatus = .unsaved
        }
    }

    private func save() {
        saveStatus = .saving
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            withAnimation { saveStatus = .saved }
        } catch {
            saveStatus = .unsaved
        }
    }
}

// MARK: - Empty State

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No note selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a note from the sidebar, or create one with ⌘N.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
