import XCTest
@testable import CAI

// MARK: - Status Pill Style Tests
// P13: every status gets a colour family AND a sentence-case label (never colour
// alone), including the wider vocabulary the backend may send via `.other`.

final class ChangeRequestStatusStyleTests: XCTestCase {
    func test_wireStatuses() {
        XCTAssertEqual(ChangeRequestStatus.blocked.style, RQStatusStyle(family: .red, label: "Blocked"))
        XCTAssertEqual(ChangeRequestStatus.planned.style, RQStatusStyle(family: .blue, label: "Planned"))
        XCTAssertEqual(ChangeRequestStatus.inProgress.style, RQStatusStyle(family: .orange, label: "In progress"))
        XCTAssertEqual(ChangeRequestStatus.completed.style, RQStatusStyle(family: .green, label: "Completed"))
    }

    func test_designVocabularyViaOther() {
        XCTAssertEqual(ChangeRequestStatus(raw: "draft").style.family, .neutral)
        XCTAssertEqual(ChangeRequestStatus(raw: "submitted").style.family, .blue)
        XCTAssertEqual(ChangeRequestStatus(raw: "in_review").style, RQStatusStyle(family: .orange, label: "In review"))
        XCTAssertEqual(ChangeRequestStatus(raw: "inreview").style.label, "In review")
        XCTAssertEqual(ChangeRequestStatus(raw: "approved").style.family, .green)
        XCTAssertEqual(ChangeRequestStatus(raw: "rejected").style.family, .red)
        XCTAssertEqual(ChangeRequestStatus(raw: "Transported").style.family, .purple)
        XCTAssertEqual(ChangeRequestStatus(raw: "closed").style.family, .muted)
    }

    func test_unknownStatus_isNeutralWithReadableLabel() {
        XCTAssertEqual(
            ChangeRequestStatus(raw: "PENDING_QA").style,
            RQStatusStyle(family: .neutral, label: "Pending qa")
        )
        XCTAssertEqual(ChangeRequestStatus(raw: "").style.label, "Unknown")
    }
}
