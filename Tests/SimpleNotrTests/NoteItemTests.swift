import Foundation
import Testing
@testable import SimpleNotr

@Suite("NoteType")
struct NoteTypeTests {

    @Test func fileExtensions() {
        #expect(NoteType.text.fileExtension == "txt")
        #expect(NoteType.markdown.fileExtension == "md")
    }

    @Test func systemImages() {
        #expect(NoteType.text.systemImage == "doc.text")
        #expect(NoteType.markdown.systemImage == "doc.richtext")
    }
}

@Suite("NoteItem")
struct NoteItemTests {

    @Test func folderWithChildrenImage() {
        let child = file(name: "child", path: "/tmp/child.md")
        let folder = NoteItem(id: url("/tmp/F"), url: url("/tmp/F"), name: "F",
                              isFolder: true, noteType: nil, children: [child])
        #expect(folder.systemImage == "folder.fill")
    }

    @Test func emptyFolderImage() {
        let folder = NoteItem(id: url("/tmp/E"), url: url("/tmp/E"), name: "E",
                              isFolder: true, noteType: nil, children: [])
        #expect(folder.systemImage == "folder")
    }

    @Test func markdownFileImage() {
        #expect(file(name: "n", path: "/tmp/n.md", type: .markdown).systemImage == "doc.richtext")
    }

    @Test func textFileImage() {
        #expect(file(name: "n", path: "/tmp/n.txt", type: .text).systemImage == "doc.text")
    }

    @Test func folderExposesListChildren() {
        let child = file(name: "a", path: "/tmp/a.md")
        let folder = NoteItem(id: url("/tmp/F"), url: url("/tmp/F"), name: "F",
                              isFolder: true, noteType: nil, children: [child])
        #expect(folder.listChildren?.count == 1)
    }

    @Test func fileListChildrenIsNil() {
        #expect(file(name: "n", path: "/tmp/n.md").listChildren == nil)
    }

    @Test func equalityBasedOnURL() {
        let u = url("/tmp/note.md")
        let a = NoteItem(id: u, url: u, name: "note",     isFolder: false, noteType: .markdown, children: nil)
        let b = NoteItem(id: u, url: u, name: "different", isFolder: false, noteType: .markdown, children: nil)
        #expect(a == b)
    }

    @Test func inequalityDifferentURL() {
        let a = file(name: "note", path: "/tmp/a.md")
        let b = file(name: "note", path: "/tmp/b.md")
        #expect(a != b)
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func file(name: String, path: String, type: NoteType = .markdown) -> NoteItem {
        let u = url(path)
        return NoteItem(id: u, url: u, name: name, isFolder: false, noteType: type, children: nil)
    }
}
