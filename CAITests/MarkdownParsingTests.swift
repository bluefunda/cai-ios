import XCTest
@testable import CAI

// MARK: - Nested list depth tracking

final class MarkdownNestedListTests: XCTestCase {

    private func listItems(_ blocks: [MarkdownBlock]) -> [MarkdownListEntry] {
        blocks.flatMap { block -> [MarkdownListEntry] in
            if case .list(let items) = block { return items }
            return []
        }
    }

    func test_flatList_isAllDepthZero() {
        let blocks = MarkdownParser.parse("- one\n- two\n- three")
        XCTAssertEqual(listItems(blocks).map(\.depth), [0, 0, 0])
    }

    func test_twoSpaceIndent_nestsOneLevelDeeper() {
        let blocks = MarkdownParser.parse("- parent\n  - child\n- sibling")
        let items = listItems(blocks)
        XCTAssertEqual(items.map(\.depth), [0, 1, 0])
        XCTAssertEqual(items.map(\.text), ["parent", "child", "sibling"])
    }

    func test_fourSpaceIndent_alsoNestsOneLevelDeeper() {
        let blocks = MarkdownParser.parse("- parent\n    - child")
        XCTAssertEqual(listItems(blocks).map(\.depth), [0, 1])
    }

    func test_depth_returnsToShallowerLevelAfterDedenting() {
        let blocks = MarkdownParser.parse("- a\n  - b\n    - c\n  - d\n- e")
        XCTAssertEqual(listItems(blocks).map(\.depth), [0, 1, 2, 1, 0])
    }

    func test_orderedParent_withUnorderedChildren_mixedInOneListBlock() {
        let blocks = MarkdownParser.parse("1. step one\n   - detail a\n   - detail b\n2. step two")
        let items = listItems(blocks)
        XCTAssertEqual(items.map(\.depth), [0, 1, 1, 0])
        XCTAssertEqual(items.map(\.ordered), [true, false, false, true])
        XCTAssertEqual(items.map(\.text), ["step one", "detail a", "detail b", "step two"])
    }

    func test_orderedItems_preserveTheirCapturedNumber() {
        let blocks = MarkdownParser.parse("5. fifth\n6. sixth")
        XCTAssertEqual(listItems(blocks).map(\.number), [5, 6])
    }
}

// MARK: - Syntax highlighting

final class SyntaxHighlightingTests: XCTestCase {

    func test_unrecognizedLanguage_rendersPlain() {
        let code = "some ```made-up``` text"
        XCTAssertEqual(String(highlightedCode(code, language: "not-a-real-lang").characters), code)
    }

    func test_noLanguage_rendersPlain() {
        let code = "plain code with no fence language"
        XCTAssertEqual(String(highlightedCode(code, language: nil).characters), code)
    }

    func test_highlighting_neverChangesVisibleText() {
        let code = "const x = \"hello\"; // a comment\nreturn 42;"
        XCTAssertEqual(String(highlightedCode(code, language: "javascript").characters), code)
    }

    func test_tokenizesKeywordStringNumberAndComment() {
        let tokens = tokenizeLine("const x = 42; // done", keywords: ["const", "let", "var"], lineCommentPrefix: "//")
        let texts = tokens.map(\.0)
        let kinds = tokens.map(\.1)
        XCTAssertEqual(texts, ["const", " ", "x", " ", "=", " ", "42", ";", " ", "// done"])
        XCTAssertEqual(kinds, [.keyword, .plain, .plain, .plain, .plain, .plain, .number, .plain, .plain, .comment])
    }

    func test_stringLiteral_isASingleToken() {
        let tokens = tokenizeLine("\"hello world\"", keywords: [], lineCommentPrefix: nil)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].0, "\"hello world\"")
        XCTAssertEqual(tokens[0].1, .string)
    }

    func test_escapedQuote_doesNotEndStringEarly() {
        let tokens = tokenizeLine("\"a \\\"quoted\\\" word\" done", keywords: [], lineCommentPrefix: nil)
        XCTAssertEqual(tokens.first?.0, "\"a \\\"quoted\\\" word\"")
        XCTAssertEqual(tokens.first?.1, .string)
    }

    func test_abapKeywords_recognized() {
        let code = "DATA lv_name TYPE string."
        XCTAssertEqual(String(highlightedCode(code, language: "abap").characters), code)
    }

    func test_sqlIsCaseInsensitiveForKeywords() {
        let tokens = tokenizeLine(
            "select * from users",
            keywords: ["select", "SELECT", "from", "FROM"],
            lineCommentPrefix: "--"
        )
        XCTAssertEqual(tokens.first { $0.0 == "select" }?.1, .keyword)
        XCTAssertEqual(tokens.first { $0.0 == "from" }?.1, .keyword)
    }
}
