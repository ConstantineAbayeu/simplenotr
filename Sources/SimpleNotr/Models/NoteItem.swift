import Foundation

// MARK: - Note Type

enum NoteType: Hashable {
    case text      // .txt
    case markdown  // .md

    var fileExtension: String {
        switch self {
        case .text:     return "txt"
        case .markdown: return "md"
        }
    }

    var systemImage: String {
        switch self {
        case .text:     return "doc.text"
        case .markdown: return "doc.richtext"
        }
    }
}

// MARK: - Note Item

struct NoteItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    var name: String        // display name (no extension for files, folder name for folders)
    var isFolder: Bool
    var noteType: NoteType? // nil for folders
    var children: [NoteItem]? // non-nil only for folders

    // For SwiftUI List(children:) — folders expose their array, files expose nil
    var listChildren: [NoteItem]? {
        isFolder ? children : nil
    }

    var systemImage: String {
        if isFolder {
            return (children?.isEmpty == false) ? "folder.fill" : "folder"
        }
        return noteType?.systemImage ?? "doc"
    }

    static func == (lhs: NoteItem, rhs: NoteItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
