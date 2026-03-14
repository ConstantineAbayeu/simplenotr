import Foundation
import AppKit

@MainActor
final class VaultManager: ObservableObject {
    @Published var vaultURL: URL?
    @Published var rootItems: [NoteItem] = []

    private let bookmarkKey = "vaultBookmarkData_v1"

    init() {
        restoreVault()
    }

    // MARK: - Vault Lifecycle

    func openVault(at url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        saveBookmark(for: url)
        vaultURL = url
        refreshFileTree()
    }

    private func restoreVault() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            _ = url.startAccessingSecurityScopedResource()
            if stale { saveBookmark(for: url) }
            vaultURL = url
            refreshFileTree()
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    // MARK: - File Tree

    func refreshFileTree() {
        guard let vaultURL else { return }
        rootItems = buildTree(at: vaultURL)
    }

    private func buildTree(at directory: URL) -> [NoteItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Folders first, then files — both alphabetical
        let sorted = contents.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        var items: [NoteItem] = []
        for url in sorted {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = buildTree(at: url)
                items.append(NoteItem(
                    id: url, url: url,
                    name: url.lastPathComponent,
                    isFolder: true, noteType: nil,
                    children: children
                ))
            } else {
                let ext = url.pathExtension.lowercased()
                guard ext == "txt" || ext == "md" else { continue }
                items.append(NoteItem(
                    id: url, url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    isFolder: false,
                    noteType: ext == "md" ? .markdown : .text,
                    children: nil
                ))
            }
        }
        return items
    }

    // MARK: - File Operations

    @discardableResult
    func createNote(named name: String, type: NoteType, in folder: URL) -> URL? {
        let fileURL = folder.appendingPathComponent("\(name).\(type.fileExtension)")
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard (try? "".write(to: fileURL, atomically: true, encoding: .utf8)) != nil else { return nil }
        refreshFileTree()
        return fileURL
    }

    @discardableResult
    func createFolder(named name: String, in parent: URL) -> URL? {
        let folderURL = parent.appendingPathComponent(name)
        guard (try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)) != nil else { return nil }
        refreshFileTree()
        return folderURL
    }

    func deleteItem(at url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refreshFileTree()
    }

    @discardableResult
    func renameItem(at url: URL, to newFullName: String) -> URL? {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newFullName)
        guard (try? FileManager.default.moveItem(at: url, to: newURL)) != nil else { return nil }
        refreshFileTree()
        return newURL
    }

    // MARK: - Search / Navigation

    func findNote(named name: String) -> NoteItem? {
        searchItems(rootItems, name: name)
    }

    func findItemByURL(_ url: URL) -> NoteItem? {
        searchByURL(rootItems, url: url)
    }

    func findNoteByRelativePath(_ path: String) -> NoteItem? {
        guard let vaultURL else { return nil }
        var clean = path
        if clean.hasPrefix("./") { clean = String(clean.dropFirst(2)) }
        if clean.hasPrefix("../") { clean = String(clean.dropFirst(3)) }
        let candidate = vaultURL.appendingPathComponent(clean)
        return searchByURL(rootItems, url: candidate)
            ?? searchByURL(rootItems, url: candidate.deletingPathExtension())
    }

    private func searchItems(_ items: [NoteItem], name: String) -> NoteItem? {
        for item in items {
            if !item.isFolder && item.name.lowercased() == name.lowercased() { return item }
            if let children = item.children, let found = searchItems(children, name: name) { return found }
        }
        return nil
    }

    private func searchByURL(_ items: [NoteItem], url: URL) -> NoteItem? {
        let targetPath = url.path
        for item in items {
            if item.url.path == targetPath { return item }
            if let children = item.children, let found = searchByURL(children, url: url) { return found }
        }
        return nil
    }
}
