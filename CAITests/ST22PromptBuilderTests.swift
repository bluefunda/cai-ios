import XCTest
@testable import CAI

// MARK: - ST22 Prompt Builder Tests (bluefunda/cai-ios#182)

final class ST22PromptBuilderTests: XCTestCase {
    func test_withRawDump_includesDumpAndSections() {
        let prompt = ST22PromptBuilder.buildPrompt(rawDump: "Category ABAP programming error")

        XCTAssertTrue(prompt.contains("## Root Cause"))
        XCTAssertTrue(prompt.contains("## Suggested Fix"))
        XCTAssertTrue(prompt.contains("## References"))
        XCTAssertTrue(prompt.contains("Category ABAP programming error"))
    }

    func test_withoutRawDump_referencesAttachedScreenshot() {
        let prompt = ST22PromptBuilder.buildPrompt(rawDump: nil)

        XCTAssertTrue(prompt.contains("attached ST22 dump screenshot"))
        XCTAssertFalse(prompt.contains("Dump:"))
    }
}
