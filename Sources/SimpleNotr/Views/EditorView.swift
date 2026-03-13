import SwiftUI

// MARK: - Editor View

struct EditorView: View {
    let item: NoteItem
    @Binding var selectedItem: NoteItem?

    @State private var content: String = ""
    @State private var saveStatus: SaveStatus = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var fileURL: URL

    private enum SaveStatus { case saved, unsaved, saving }

    init(item: NoteItem, selectedItem: Binding<NoteItem?>) {
        self.item = item
        self._selectedItem = selectedItem
        self._fileURL = State(initialValue: item.url)
    }

    var body: some View {
        editorContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { loadContent() }
            .onChange(of: item) { newItem in
                flushSave()
                fileURL = newItem.url
                loadContent()
            }
            .onDisappear { flushSave() }
    }

    @ViewBuilder
    private var editorContent: some View {
        if item.noteType == .markdown {
            markdownSplitView
        } else {
            plainTextView
        }
    }

    // MARK: - Split pane for Markdown

    private var markdownSplitView: some View {
        HSplitView {
            PlainTextEditorView(
                text: $content,
                font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                onChange: scheduleAutosave
            )
            .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)

            MarkdownPreviewView(content: content, selectedItem: $selectedItem)
                .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Plain editor for TXT

    private var plainTextView: some View {
        PlainTextEditorView(
            text: $content,
            font: .systemFont(ofSize: 14),
            onChange: scheduleAutosave
        )
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
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
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
