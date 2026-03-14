import Foundation
import Testing
@testable import SimpleNotr

@Suite("MarkdownProcessor – sanitize")
struct SanitizeTests {

    // MARK: WikiLinks

    @Test func wikiLinkBasic() {
        #expect(MarkdownProcessor.sanitize("See [[MyNote]]") == "See [MyNote](note://MyNote)")
    }

    @Test func wikiLinkWithDisplayText() {
        #expect(MarkdownProcessor.sanitize("[[MyNote|click here]]") == "[click here](note://MyNote)")
    }

    @Test func multipleWikiLinks() {
        #expect(MarkdownProcessor.sanitize("[[A]] and [[B]]") == "[A](note://A) and [B](note://B)")
    }

    // MARK: External links stripped

    @Test func externalHttpLinkStripped() {
        #expect(MarkdownProcessor.sanitize("[click](https://example.com)") == "click")
    }

    @Test func externalHttpsLinkStripped() {
        #expect(MarkdownProcessor.sanitize("[visit](http://example.com/page)") == "visit")
    }

    @Test func ftpLinkStripped() {
        #expect(MarkdownProcessor.sanitize("[file](ftp://files.example.com)") == "file")
    }

    @Test func mailtoLinkStripped() {
        #expect(MarkdownProcessor.sanitize("[email me](mailto:test@example.com)") == "email me")
    }

    @Test func externalImageStripped() {
        #expect(MarkdownProcessor.sanitize("![logo](https://example.com/logo.png)") == "[external image]")
    }

    // MARK: Relative links

    @Test func relativeLinkDotSlash() {
        #expect(MarkdownProcessor.sanitize("[note](./OtherNote.md)") == "[note](note://OtherNote.md)")
    }

    @Test func relativeLinkDotDotSlash() {
        #expect(MarkdownProcessor.sanitize("[note](../OtherNote.md)") == "[note](note://OtherNote.md)")
    }

    @Test func noteSchemePassesThrough() {
        let input = "[note](note://MyNote)"
        #expect(MarkdownProcessor.sanitize(input) == input)
    }
}

@Suite("MarkdownProcessor – parseBlocks")
struct ParseBlocksTests {

    // MARK: Headings

    @Test func headingLevel1() {
        let blocks = MarkdownProcessor.parseBlocks("# Hello")
        #expect(blocks.count == 1)
        guard case .heading(let level, let raw) = blocks[0] else { Issue.record("Expected heading"); return }
        #expect(level == 1)
        #expect(raw == "Hello")
    }

    @Test func headingLevel3() {
        let blocks = MarkdownProcessor.parseBlocks("### Deep")
        guard case .heading(let level, _) = blocks[0] else { Issue.record("Expected heading"); return }
        #expect(level == 3)
    }

    @Test func hashWithoutSpaceIsNotHeading() {
        let blocks = MarkdownProcessor.parseBlocks("#nospace")
        guard case .paragraph(_) = blocks[0] else { Issue.record("Expected paragraph"); return }
    }

    // MARK: Thematic breaks

    @Test func thematicBreakDashes() {
        let blocks = MarkdownProcessor.parseBlocks("---")
        guard case .thematicBreak = blocks[0] else { Issue.record("Expected thematicBreak"); return }
    }

    @Test func thematicBreakAsterisks() {
        let blocks = MarkdownProcessor.parseBlocks("***")
        guard case .thematicBreak = blocks[0] else { Issue.record("Expected thematicBreak"); return }
    }

    @Test func thematicBreakUnderscores() {
        let blocks = MarkdownProcessor.parseBlocks("___")
        guard case .thematicBreak = blocks[0] else { Issue.record("Expected thematicBreak"); return }
    }

    @Test func twoDashesIsNotThematicBreak() {
        let blocks = MarkdownProcessor.parseBlocks("--")
        guard case .paragraph(_) = blocks[0] else { Issue.record("Two dashes should be paragraph"); return }
    }

    // MARK: Code blocks

    @Test func fencedCodeBlockBacktick() {
        let blocks = MarkdownProcessor.parseBlocks("```\nlet x = 1\n```")
        #expect(blocks.count == 1)
        guard case .codeBlock(let lang, let code) = blocks[0] else { Issue.record("Expected codeBlock"); return }
        #expect(lang == nil)
        #expect(code == "let x = 1")
    }

    @Test func fencedCodeBlockWithLanguage() {
        let blocks = MarkdownProcessor.parseBlocks("```swift\nlet x = 1\n```")
        guard case .codeBlock(let lang, _) = blocks[0] else { Issue.record("Expected codeBlock"); return }
        #expect(lang == "swift")
    }

    @Test func fencedCodeBlockTilde() {
        let blocks = MarkdownProcessor.parseBlocks("~~~\ncode here\n~~~")
        guard case .codeBlock(_, let code) = blocks[0] else { Issue.record("Expected codeBlock"); return }
        #expect(code == "code here")
    }

    // MARK: Lists

    @Test func bulletListDash() {
        let blocks = MarkdownProcessor.parseBlocks("- alpha\n- beta\n- gamma")
        #expect(blocks.count == 1)
        guard case .bulletList(let items) = blocks[0] else { Issue.record("Expected bulletList"); return }
        #expect(items == ["alpha", "beta", "gamma"])
    }

    @Test func bulletListAsterisk() {
        let blocks = MarkdownProcessor.parseBlocks("* one\n* two")
        guard case .bulletList(let items) = blocks[0] else { Issue.record("Expected bulletList"); return }
        #expect(items.count == 2)
    }

    @Test func orderedList() {
        let blocks = MarkdownProcessor.parseBlocks("1. First\n2. Second\n3. Third")
        #expect(blocks.count == 1)
        guard case .orderedList(let items) = blocks[0] else { Issue.record("Expected orderedList"); return }
        #expect(items == ["First", "Second", "Third"])
    }

    // MARK: Blockquote

    @Test func blockquote() {
        let blocks = MarkdownProcessor.parseBlocks("> This is a quote")
        guard case .blockquote(let raw) = blocks[0] else { Issue.record("Expected blockquote"); return }
        #expect(raw == "This is a quote")
    }

    // MARK: Paragraph

    @Test func paragraph() {
        let blocks = MarkdownProcessor.parseBlocks("Hello world")
        guard case .paragraph(let raw) = blocks[0] else { Issue.record("Expected paragraph"); return }
        #expect(raw == "Hello world")
    }

    @Test func blankLinesSkipped() {
        let blocks = MarkdownProcessor.parseBlocks("\n\n# Title\n\nParagraph\n\n")
        #expect(blocks.count == 2)
    }

    @Test func mixedBlocks() {
        let input = "# Heading\n\nA paragraph.\n\n- item one\n- item two\n\n---"
        let blocks = MarkdownProcessor.parseBlocks(input)
        #expect(blocks.count == 4)
        guard case .heading(_, _)  = blocks[0] else { Issue.record("Expected heading");   return }
        guard case .paragraph(_)   = blocks[1] else { Issue.record("Expected paragraph"); return }
        guard case .bulletList(_)  = blocks[2] else { Issue.record("Expected list");      return }
        guard case .thematicBreak  = blocks[3] else { Issue.record("Expected break");     return }
    }
}
