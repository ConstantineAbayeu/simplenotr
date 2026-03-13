import Foundation

// MARK: - Block Types

enum MDBlock {
    case heading(level: Int, raw: String)   // raw = text after the #s
    case paragraph(raw: String)             // raw inline markdown
    case codeBlock(language: String?, code: String)
    case bulletList(items: [String])        // each item = raw inline markdown
    case orderedList(items: [String])
    case blockquote(raw: String)            // inner raw text (may contain nested markdown)
    case thematicBreak
}

// MARK: - Processor

enum MarkdownProcessor {

    // MARK: Sanitize
    //
    // Security contract:
    //   • External URLs (http/https/ftp/mailto) in links and images are stripped.
    //   • Only note:// (internal navigation) and relative-path links survive.
    //   • WikiLinks [[Name]] → note://Name links.
    //   • No bare-URL autolink processing happens here; that is blocked in the
    //     view layer via the openURL environment.
    //
    static func sanitize(_ text: String) -> String {
        var t = text

        // 1. [[Target|Display]] → [Display](note://Target)
        t = regexReplace(t,
            pattern: #"\[\[([^\|\]]+)\|([^\]]+)\]\]"#,
            template: "[$2](note://$1)")

        // 2. [[Target]] → [Target](note://Target)
        t = regexReplace(t,
            pattern: #"\[\[([^\]]+)\]\]"#,
            template: "[$1](note://$1)")

        // 3. External images: ![alt](https?://…) → [external image]
        t = regexReplace(t,
            pattern: #"!\[([^\]]*)\]\(https?://[^\)]*\)"#,
            template: "\\[external image\\]")

        // 4. External links: [text](https?://…) → text  (keep display only)
        t = regexReplace(t,
            pattern: #"\[([^\]]+)\]\(https?://[^\)]*\)"#,
            template: "$1")

        // 5. ftp:// and mailto: links → display text only
        t = regexReplace(t,
            pattern: #"\[([^\]]+)\]\((ftp|mailto):[^\)]*\)"#,
            template: "$1")

        // 6. Relative links: [text](./path) or [text](../path) → note://path
        t = regexReplace(t,
            pattern: #"\[([^\]]+)\]\(\.\./([^\)]+)\)"#,
            template: "[$1](note://$2)")
        t = regexReplace(t,
            pattern: #"\[([^\]]+)\]\(\.\/([^\)]+)\)"#,
            template: "[$1](note://$2)")

        return t
    }

    // MARK: Parse Blocks

    static func parseBlocks(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line — skip
            if trimmed.isEmpty { i += 1; continue }

            // ATX Heading: # … ######
            if let h = matchHeading(trimmed) {
                blocks.append(.heading(level: h.level, raw: h.text))
                i += 1; continue
            }

            // Thematic break: ---, ***, ___
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                i += 1; continue
            }

            // Fenced code block: ``` or ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // skip closing fence
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Blockquote: >
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("> ") { quoteLines.append(String(l.dropFirst(2))); i += 1 }
                    else if l == ">"    { quoteLines.append(""); i += 1 }
                    else if l.isEmpty  { break }
                    else               { quoteLines.append(l); i += 1 } // lazy continuation
                }
                blocks.append(.blockquote(raw: quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet list: -, *, +
            if isBulletItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletItem(l) { items.append(String(l.dropFirst(2))); i += 1 }
                    else if l.isEmpty  { i += 1; break }
                    else               { break }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Ordered list: 1. 2. …
            if let first = matchOrderedItem(trimmed) {
                var items: [String] = [first]
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if let next = matchOrderedItem(l) { items.append(next); i += 1 }
                    else if l.isEmpty { i += 1; break }
                    else { break }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Paragraph: collect until blank line or block-level element
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if matchHeading(t) != nil { break }
                if isThematicBreak(t) { break }
                if t.hasPrefix("```") || t.hasPrefix("~~~") { break }
                if t.hasPrefix(">") { break }
                if isBulletItem(t) { break }
                if matchOrderedItem(t) != nil { break }
                paraLines.append(l)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(raw: paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    // MARK: - Private Helpers

    private static func matchHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var rest = line[line.startIndex...]
        while level < 6 && rest.first == "#" { level += 1; rest = rest.dropFirst() }
        guard level > 0, rest.first == " " else { return nil }
        return (level, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let s = line.filter { !$0.isWhitespace }
        return s.count >= 3 && (s == String(repeating: "-", count: s.count)
                             || s == String(repeating: "*", count: s.count)
                             || s == String(repeating: "_", count: s.count))
    }

    private static func isBulletItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func matchOrderedItem(_ line: String) -> String? {
        guard let r = line.range(of: #"^\d+\. "#, options: .regularExpression) else { return nil }
        return String(line[r.upperBound...])
    }

    /// NSRegularExpression-based replace supporting $1, $2 capture group references.
    static func regexReplace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
