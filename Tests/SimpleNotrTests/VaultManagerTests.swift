import Foundation
import Testing
@testable import SimpleNotr

// Each test gets its own VaultManager + temp directory via the struct init.
// Temp dirs are left in /tmp after tests; the OS clears them on reboot.
@Suite("VaultManager")
@MainActor
struct VaultManagerTests {

    let vault: VaultManager
    let tempDir: URL

    init() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleNotrTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir
        self.vault = VaultManager()
        self.vault.openVault(at: dir)
    }

    // MARK: - createNote

    @Test func createNoteProducesFile() throws {
        let fileURL = try #require(vault.createNote(named: "Hello", type: .markdown, in: tempDir))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(fileURL.pathExtension == "md")
    }

    @Test func createTextNoteExtension() throws {
        let fileURL = try #require(vault.createNote(named: "MyNote", type: .text, in: tempDir))
        #expect(fileURL.pathExtension == "txt")
    }

    @Test func createNoteAppearsInTree() {
        vault.createNote(named: "TreeNote", type: .markdown, in: tempDir)
        #expect(vault.findNote(named: "TreeNote") != nil)
    }

    @Test func createNoteDuplicateReturnsNil() {
        vault.createNote(named: "Dupe", type: .markdown, in: tempDir)
        #expect(vault.createNote(named: "Dupe", type: .markdown, in: tempDir) == nil)
    }

    // MARK: - createFolder

    @Test func createFolderProducesDirectory() throws {
        let folderURL = try #require(vault.createFolder(named: "SubFolder", in: tempDir))
        let isDir = (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        #expect(isDir)
    }

    @Test func createFolderAppearsInTree() throws {
        let folderURL = try #require(vault.createFolder(named: "Docs", in: tempDir))
        let item = vault.findItemByURL(folderURL)
        #expect(item != nil)
        #expect(item?.isFolder == true)
    }

    @Test func createFolderDuplicateReturnsNil() {
        vault.createFolder(named: "OnlyOnce", in: tempDir)
        #expect(vault.createFolder(named: "OnlyOnce", in: tempDir) == nil)
    }

    // MARK: - deleteItem

    @Test func deleteNoteRemovesFromTree() throws {
        let fileURL = try #require(vault.createNote(named: "ToDelete", type: .text, in: tempDir))
        vault.deleteItem(at: fileURL)
        #expect(vault.findNote(named: "ToDelete") == nil)
    }

    @Test func deleteFolderRemovesFromTree() throws {
        let folderURL = try #require(vault.createFolder(named: "GoneFolder", in: tempDir))
        vault.deleteItem(at: folderURL)
        #expect(vault.findItemByURL(folderURL) == nil)
    }

    // MARK: - renameItem

    @Test func renameNoteChangesName() throws {
        let oldURL = try #require(vault.createNote(named: "OldName", type: .markdown, in: tempDir))
        let newURL = vault.renameItem(at: oldURL, to: "NewName.md")
        #expect(newURL != nil)
        #expect(vault.findNote(named: "OldName") == nil)
        #expect(vault.findNote(named: "NewName") != nil)
    }

    @Test func renameFolderChangesName() throws {
        let oldURL = try #require(vault.createFolder(named: "FolderA", in: tempDir))
        let newURL = try #require(vault.renameItem(at: oldURL, to: "FolderB"))
        #expect(vault.findItemByURL(oldURL) == nil)
        #expect(vault.findItemByURL(newURL) != nil)
    }

    // MARK: - findNote

    @Test func findNoteByName() {
        vault.createNote(named: "Searchable", type: .markdown, in: tempDir)
        let item = vault.findNote(named: "Searchable")
        #expect(item != nil)
        #expect(item?.isFolder == false)
    }

    @Test func findNoteCaseInsensitive() {
        vault.createNote(named: "CaseTest", type: .text, in: tempDir)
        #expect(vault.findNote(named: "casetest") != nil)
        #expect(vault.findNote(named: "CASETEST") != nil)
    }

    @Test func findNoteInSubfolder() throws {
        let sub = try #require(vault.createFolder(named: "Sub", in: tempDir))
        vault.createNote(named: "Nested", type: .markdown, in: sub)
        #expect(vault.findNote(named: "Nested") != nil)
    }

    @Test func findNoteMissingReturnsNil() {
        #expect(vault.findNote(named: "DoesNotExist") == nil)
    }

    // MARK: - findItemByURL

    @Test func findItemByURL() throws {
        let fileURL = try #require(vault.createNote(named: "URLTest", type: .text, in: tempDir))
        let item = vault.findItemByURL(fileURL)
        #expect(item != nil)
        #expect(item?.url == fileURL)
    }

    @Test func findItemByURLMissingReturnsNil() {
        #expect(vault.findItemByURL(tempDir.appendingPathComponent("ghost.md")) == nil)
    }

    // MARK: - findNoteByRelativePath

    @Test func findNoteByRelativePath() {
        vault.createNote(named: "RelNote", type: .markdown, in: tempDir)
        #expect(vault.findNoteByRelativePath("RelNote.md") != nil)
    }

    @Test func findNoteByRelativePathDotSlash() {
        vault.createNote(named: "DotSlash", type: .text, in: tempDir)
        #expect(vault.findNoteByRelativePath("./DotSlash.txt") != nil)
    }

    // MARK: - buildTree sorting

    @Test func foldersBeforeFiles() {
        vault.createNote(named: "aaa", type: .text, in: tempDir)
        vault.createFolder(named: "zzz", in: tempDir)
        #expect(vault.rootItems.first?.isFolder == true)
    }

    @Test func filesAlphabeticallySorted() {
        vault.createNote(named: "Charlie", type: .text, in: tempDir)
        vault.createNote(named: "Alpha",   type: .text, in: tempDir)
        vault.createNote(named: "Bravo",   type: .text, in: tempDir)
        let names = vault.rootItems.filter { !$0.isFolder }.map { $0.name }
        #expect(names == ["Alpha", "Bravo", "Charlie"])
    }

    @Test func nonNoteFilesExcluded() throws {
        let jsonURL = tempDir.appendingPathComponent("data.json")
        try "{}".write(to: jsonURL, atomically: true, encoding: .utf8)
        vault.refreshFileTree()
        #expect(vault.findItemByURL(jsonURL) == nil)
    }
}
