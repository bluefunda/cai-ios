import XCTest
@testable import CAI

// MARK: - Share Card Formatter Tests (bluefunda/cai-ios#197)

final class ShareCardFormatterTests: XCTestCase {
    func test_shortAnswer_returnedUnchanged() {
        let answer = "Dunning is the process of reminding customers about overdue payments."
        XCTAssertEqual(ShareCardFormatter.truncatedAnswer(answer), answer)
    }

    func test_longAnswer_truncatedWithEllipsis() {
        let answer = String(repeating: "a", count: ShareCardFormatter.maxAnswerLength + 50)
        let result = ShareCardFormatter.truncatedAnswer(answer)

        XCTAssertTrue(result.hasSuffix("…"))
        XCTAssertLessThan(result.count, answer.count)
    }

    func test_answerAtExactLimit_returnedUnchanged() {
        let answer = String(repeating: "a", count: ShareCardFormatter.maxAnswerLength)
        XCTAssertEqual(ShareCardFormatter.truncatedAnswer(answer), answer)
    }
}
