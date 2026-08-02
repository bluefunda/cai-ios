import XCTest
@testable import CAI

// MARK: - Share Card Formatter Tests (bluefunda/cai-ios#197)

final class ShareCardFormatterTests: XCTestCase {
    func test_shortAnswer_returnedUnchanged() {
        let answer = "Dunning is the process of reminding customers about overdue payments."
        XCTAssertEqual(ShareCardFormatter.truncatedAnswer(answer), answer)
    }

    func test_longAnswer_truncatedWithContinuedNote() {
        let answer = String(repeating: "a", count: ShareCardFormatter.maxAnswerLength + 50)
        let result = ShareCardFormatter.truncatedAnswer(answer)

        XCTAssertTrue(result.contains("Continued in the BlueFunda AI app"))
        XCTAssertTrue(result.hasPrefix(String(repeating: "a", count: ShareCardFormatter.maxAnswerLength)))
    }

    func test_realisticLongStructuredAnswer_notOverTruncated() {
        // Guards bluefunda/cai-ios#197's reported bug: a long but realistic
        // structured technical answer (headers, tables, code) was being cut
        // down to almost nothing under the old 600-char limit.
        let section = "## Section\n\nSome explanatory text.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n"
        let answer = String(repeating: section, count: 15) // ~3000 chars
        let result = ShareCardFormatter.truncatedAnswer(answer)

        XCTAssertEqual(result, answer, "a realistic long answer should survive intact under the new cap")
    }

    func test_answerAtExactLimit_returnedUnchanged() {
        let answer = String(repeating: "a", count: ShareCardFormatter.maxAnswerLength)
        XCTAssertEqual(ShareCardFormatter.truncatedAnswer(answer), answer)
    }
}
