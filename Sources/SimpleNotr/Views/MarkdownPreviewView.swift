import SwiftUI

// MARK: - Preview Root

struct MarkdownPreviewView: View {
    let content: String
    @Binding var selectedItem: NoteItem?
    @EnvironmentObject var vaultManager: VaultManager

    private var blocks: [MDBlock] {
        MarkdownProcessor.parseBlocks(MarkdownProcessor.sanitize(content))
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                        .padding(.bottom, bottomPadding(for: block))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        // ── Security: intercept ALL link activations ─────────────────────────
        // Only note:// (internal wiki links) are allowed through.
        // Every other scheme (http, https, ftp, file, mailto, …) is discarded.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "note" else { return .discarded }
            let target = url.host ?? String(url.path.dropFirst()) // drop leading /
            navigateTo(target)
            return .handled
        })
        // ─────────────────────────────────────────────────────────────────────
    }

    private func navigateTo(_ target: String) {
        if let item = vaultManager.findNote(named: target) {
            selectedItem = item
        } else if let item = vaultManager.findNoteByRelativePath(target) {
            selectedItem = item
        }
    }

    private func bottomPadding(for block: MDBlock) -> CGFloat {
        switch block {
        case .thematicBreak:    return 16
        case .heading(1, _):   return 12
        case .heading(2, _):   return 10
        case .heading:          return 8
        case .codeBlock:        return 12
        default:                return 8
        }
    }
}

// MARK: - Block Renderer

struct BlockView: View {
    let block: MDBlock
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch block {

        case .heading(let level, let raw):
            headingView(level: level, text: raw)

        case .paragraph(let raw):
            inlineText(raw)
                .lineSpacing(5)

        case .codeBlock(_, let code):
            codeBlockView(code)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 12)
                        inlineText(item)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, alignment: .trailing)
                            .monospacedDigit()
                        inlineText(item)
                    }
                }
            }

        case .blockquote(let raw):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                inlineText(raw)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: Heading

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .padding(.top, level == 1 ? 10 : 4)
            if level <= 2 {
                Divider()
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 28)
        case 2: return .system(size: 22)
        case 3: return .system(size: 18)
        case 4: return .system(size: 15)
        case 5: return .system(size: 13)
        default: return .system(size: 12)
        }
    }

    // MARK: Code Block

    @ViewBuilder
    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.isEmpty ? " " : code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.35)
                : Color.gray.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Inline Text
    //
    // Uses SwiftUI's AttributedString markdown parser for bold, italic, inline code.
    // External URLs have already been stripped by MarkdownProcessor.sanitize(), so
    // the only links that survive are note:// internal links, handled by openURL above.

    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(raw)
                .textSelection(.enabled)
        }
    }
}
