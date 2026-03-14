import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var selectedItem: NoteItem?
    @State private var openItems: [NoteItem] = []
    @State private var showVaultPicker = false
    @State private var cmdWMonitor: Any?
    @State private var cursorPositions: [URL: Int] = [:]

    @AppStorage("sn.showPreview")   private var showPreview = true
    @AppStorage("sn.previewLayout") private var previewLayoutRaw = "sideBySide"

    private var selectedHasPreview: Bool {
        selectedItem?.noteType == .markdown || selectedItem?.noteType == .mermaid
    }

    var body: some View {
        Group {
            if vaultManager.vaultURL == nil {
                WelcomeView(showVaultPicker: $showVaultPicker)
            } else {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    SidebarView(selectedItem: $selectedItem)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 380)
                } detail: {
                    Group {
                        if let item = selectedItem, !item.isFolder {
                            EditorView(item: item, selectedItem: $selectedItem, cursorPositions: $cursorPositions)
                        } else {
                            EmptyEditorView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if selectedHasPreview {
                            HStack(spacing: 2) {
                                if showPreview {
                                    Menu {
                                        Button {
                                            previewLayoutRaw = "sideBySide"
                                        } label: {
                                            Label("Side by Side", systemImage: "rectangle.split.2x1")
                                        }
                                        Button {
                                            previewLayoutRaw = "topBottom"
                                        } label: {
                                            Label("Top / Bottom", systemImage: "rectangle.split.1x2")
                                        }
                                    } label: {
                                        Image(systemName: previewLayoutRaw == "sideBySide"
                                              ? "rectangle.split.2x1"
                                              : "rectangle.split.1x2")
                                        .frame(width: 24, height: 24)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("Preview Layout")
                                }
                                Button {
                                    showPreview.toggle()
                                } label: {
                                    Image(systemName: showPreview ? "eye.slash" : "eye")
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.borderless)
                                .help(showPreview ? "Hide Preview (⌘P)" : "Show Preview (⌘P)")
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            TabBarView(openItems: $openItems, selectedItem: $selectedItem)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .fileImporter(
            isPresented: $showVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vaultManager.openVault(at: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVault)) { _ in
            showVaultPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNote)) { note in
            if let name = note.object as? String,
               let item = vaultManager.findNote(named: name) {
                selectedItem = item
            }
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem, !newItem.isFolder else { return }
            if !openItems.contains(newItem) {
                openItems.append(newItem)
            }
        }
        .onChange(of: vaultManager.rootItems) { _ in
            let existingPaths = Set(flattenItems(vaultManager.rootItems).map { $0.url.path })
            openItems = openItems.filter { existingPaths.contains($0.url.path) }
            if let sel = selectedItem, !sel.isFolder, !openItems.contains(sel) {
                selectedItem = openItems.last
            }
        }
        .onChange(of: vaultManager.vaultURL) { _ in
            openItems = []
            selectedItem = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            closeActiveTab()
        }
        .onAppear {
            cmdWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 13 && event.modifierFlags.contains(.command) && !self.openItems.isEmpty {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let m = cmdWMonitor { NSEvent.removeMonitor(m) }
            cmdWMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
            navigateTabs(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousTab)) { _ in
            navigateTabs(by: -1)
        }
    }

    private func closeActiveTab() {
        guard let current = selectedItem, let idx = openItems.firstIndex(of: current) else {
            if !openItems.isEmpty { openItems.removeLast() }
            return
        }
        openItems.remove(at: idx)
        selectedItem = openItems.isEmpty ? nil : openItems[min(idx, openItems.count - 1)]
    }

    private func navigateTabs(by offset: Int) {
        guard !openItems.isEmpty else { return }
        let current = openItems.firstIndex(where: { $0 == selectedItem }) ?? 0
        let next = (current + offset + openItems.count) % openItems.count
        selectedItem = openItems[next]
    }

    private func flattenItems(_ items: [NoteItem]) -> [NoteItem] {
        items.flatMap { item -> [NoteItem] in
            if item.isFolder, let children = item.children {
                return flattenItems(children)
            }
            return [item]
        }
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @Binding var openItems: [NoteItem]
    @Binding var selectedItem: NoteItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openItems) { item in
                    TabItemView(
                        item: item,
                        isSelected: selectedItem == item,
                        onSelect: { selectedItem = item },
                        onClose: { close(item) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
        .background(.bar)
    }

    private func close(_ item: NoteItem) {
        guard let idx = openItems.firstIndex(of: item) else { return }
        openItems.remove(at: idx)
        if selectedItem == item {
            selectedItem = openItems.isEmpty ? nil : openItems[min(idx, openItems.count - 1)]
        }
    }
}

struct TabItemView: View {
    let item: NoteItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .imageScale(.small)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .frame(maxWidth: 120)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Close tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
    }
}
