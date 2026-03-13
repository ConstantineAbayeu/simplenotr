import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Binding var selectedItem: NoteItem?

    @State private var renamingItem: NoteItem?
    @State private var renameText = ""
    @State private var showDeleteAlert = false
    @State private var itemToDelete: NoteItem?
    @State private var expandedFolders: Set<URL> = []
    @State private var sidebarFocused = false
    @State private var focusedItem: NoteItem?   // keyboard cursor, separate from open file
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            vaultHeader
            Divider()
            fileList
            Divider()
            bottomToolbar
        }
        .onReceive(NotificationCenter.default.publisher(for: .newMarkdownNote)) { _ in
            createNote(type: .markdown)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTextNote)) { _ in
            createNote(type: .text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in
            createFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { _ in
            sidebarFocused = true
        }
        .onAppear { setupKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        // When navigating to a note externally (wikilinks), expand its ancestors.
        .onChange(of: selectedItem) { item in
            if let item { expandAncestors(of: item, in: vaultManager.rootItems) }
        }
        .alert("Delete \"\(itemToDelete?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                if let item = itemToDelete {
                    if selectedItem == item { selectedItem = nil }
                    vaultManager.deleteItem(at: item.url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the item to the Trash.")
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var vaultHeader: some View {
        if let url = vaultManager.vaultURL {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.small)
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    itemRows(vaultManager.rootItems, depth: 0)
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedItem) { item in
                if let item {
                    withAnimation { proxy.scrollTo(item.id, anchor: .center) }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func itemRows(_ items: [NoteItem], depth: Int) -> some View {
        ForEach(items) { item in
            SidebarRow(
                item: item,
                depth: depth,
                isSelected: selectedItem == item,
                isExpanded: expandedFolders.contains(item.url),
                renamingItem: $renamingItem,
                renameText: $renameText,
                selectedItem: $selectedItem,
                onTap: { handleTap(item) },
                onToggle: { toggleFolder(item) },
                onRename: { renamingItem = item; renameText = item.name },
                onDelete: { itemToDelete = item; showDeleteAlert = true }
            )
            .id(item.id)

            if item.isFolder && expandedFolders.contains(item.url) {
                AnyView(itemRows(item.children ?? [], depth: depth + 1))
            }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    createNote(type: .markdown)
                } label: {
                    Label("New Markdown Note", systemImage: "doc.richtext")
                }
                Button {
                    createNote(type: .text)
                } label: {
                    Label("New Text Note", systemImage: "doc.text")
                }
                Divider()
                Button {
                    createFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("New note or folder")

            Spacer()

            Button {
                vaultManager.refreshFileTree()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Refresh vault")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func handleTap(_ item: NoteItem) {
        selectedItem = item
        sidebarFocused = true
        if item.isFolder { toggleFolder(item) }
    }

    private func toggleFolder(_ item: NoteItem) {
        if expandedFolders.contains(item.url) {
            expandedFolders.remove(item.url)
        } else {
            expandedFolders.insert(item.url)
        }
    }

    private func createNote(type: NoteType) {
        let folder = activeFolder
        let base = "Untitled"
        let ext = type.fileExtension
        var name = base
        var counter = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).\(ext)").path) {
            name = "\(base) \(counter)"
            counter += 1
        }
        expandedFolders.insert(folder)
        if let url = vaultManager.createNote(named: name, type: type, in: folder) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let item = vaultManager.findItemByURL(url) {
                    selectedItem = item
                    renamingItem = item
                    renameText = item.name
                }
            }
        }
    }

    private func createFolder() {
        let parent = activeFolder
        var name = "New Folder"
        var counter = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            name = "New Folder \(counter)"
            counter += 1
        }
        expandedFolders.insert(parent)
        if let url = vaultManager.createFolder(named: name, in: parent) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let item = vaultManager.findItemByURL(url) {
                    selectedItem = item
                    renamingItem = item
                    renameText = item.name
                }
            }
        }
    }

    private var activeFolder: URL {
        if let item = selectedItem {
            return item.isFolder ? item.url : item.url.deletingLastPathComponent()
        }
        return vaultManager.vaultURL ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Keyboard Navigation

    private var flatVisibleItems: [NoteItem] { flatten(vaultManager.rootItems) }

    private func flatten(_ items: [NoteItem]) -> [NoteItem] {
        items.flatMap { item -> [NoteItem] in
            var result = [item]
            if item.isFolder && expandedFolders.contains(item.url) {
                result += flatten(item.children ?? [])
            }
            return result
        }
    }

    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.sidebarFocused else { return event }
            switch event.keyCode {
            case 125: self.moveSelection(by: 1);  return nil   // Down
            case 126: self.moveSelection(by: -1); return nil   // Up
            case 123: self.navigateLeft();         return nil   // Left
            case 124: self.navigateRight();        return nil   // Right
            case 36, 76, 49:                                    // Return / Space
                self.confirmSelection(); return nil
            case 53:                                            // Escape
                self.sidebarFocused = false; return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func moveSelection(by offset: Int) {
        let flat = flatVisibleItems
        guard !flat.isEmpty else { return }
        if let current = selectedItem, let idx = flat.firstIndex(of: current) {
            let next = (idx + offset).clamped(to: 0...(flat.count - 1))
            selectedItem = flat[next]
        } else {
            selectedItem = offset > 0 ? flat.first : flat.last
        }
    }

    private func navigateLeft() {
        guard let item = selectedItem else { return }
        if item.isFolder && expandedFolders.contains(item.url) {
            expandedFolders.remove(item.url)
        } else if let parent = findParent(of: item, in: vaultManager.rootItems) {
            selectedItem = parent
        }
    }

    private func navigateRight() {
        guard let item = selectedItem, item.isFolder else { return }
        if expandedFolders.contains(item.url) {
            if let first = item.children?.first { selectedItem = first }
        } else {
            expandedFolders.insert(item.url)
        }
    }

    private func confirmSelection() {
        guard let item = selectedItem else { return }
        if item.isFolder {
            toggleFolder(item)
        } else {
            sidebarFocused = false
            if let tv = findFirstView(ofType: NSTextView.self, in: NSApp.keyWindow?.contentView) {
                NSApp.keyWindow?.makeFirstResponder(tv)
            }
        }
    }

    private func findParent(of target: NoteItem, in items: [NoteItem]) -> NoteItem? {
        for item in items {
            guard let children = item.children else { continue }
            if children.contains(target) { return item }
            if let found = findParent(of: target, in: children) { return found }
        }
        return nil
    }

    private func expandAncestors(of target: NoteItem, in items: [NoteItem]) {
        for item in items {
            guard let children = item.children else { continue }
            if children.contains(target) || children.contains(where: { containsDescendant(target, in: $0) }) {
                expandedFolders.insert(item.url)
                expandAncestors(of: target, in: children)
                return
            }
        }
    }

    private func containsDescendant(_ target: NoteItem, in item: NoteItem) -> Bool {
        guard let children = item.children else { return false }
        return children.contains(target) || children.contains(where: { containsDescendant(target, in: $0) })
    }

    private func findFirstView<T: NSView>(ofType type: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for sub in root.subviews {
            if let found = findFirstView(ofType: type, in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let item: NoteItem
    let depth: Int
    let isSelected: Bool
    let isExpanded: Bool
    @Binding var renamingItem: NoteItem?
    @Binding var renameText: String
    @Binding var selectedItem: NoteItem?
    let onTap: () -> Void
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var vaultManager: VaultManager
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 16)
            }

            if renamingItem == item {
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.isFolder ? Color.accentColor : .primary)
                    .imageScale(.small)
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingItem = nil }
                    .onAppear { fieldFocused = true }
            } else {
                if item.isFolder {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .onTapGesture { onToggle() }
                } else {
                    Spacer().frame(width: 16)
                }
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.isFolder ? Color.accentColor : .primary)
                    .imageScale(.small)
                Text(item.name)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            isSelected && renamingItem != item
                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.6)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture { if renamingItem != item { onTap() } }
        .contextMenu {
            Button("Rename") { onRename() }
            Button("Delete", role: .destructive) { onDelete() }
            if !item.isFolder {
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.name else { renamingItem = nil; return }
        let ext = item.isFolder ? "" : ".\(item.url.pathExtension)"
        if let newURL = vaultManager.renameItem(at: item.url, to: "\(trimmed)\(ext)") {
            if selectedItem == item {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    selectedItem = vaultManager.findItemByURL(newURL)
                }
            }
        }
        renamingItem = nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
