import XCTest
@testable import CAI

// MARK: - BlueRequests Wire Model Tests
// Ported from trm-ios (TRMTests/APIModelsTests.swift).

final class RequestsAPIModelsTests: XCTestCase {
    /// Shape confirmed against a live response and trm's own frontend source (no OpenAPI
    /// spec exists) — a truncated real sample looked like:
    /// {"combinedResponse":[{"changeRequest":{"id":32,"archive":false,"description":
    /// "Cloud files in BlueFunda AI is not working","importId":"","projectId":28,
    /// "releaseId":"","requestId":"","requestType":"7454...
    func testDecodeChangeRequestListResponse() throws {
        let json = Data("""
        {
            "combinedResponse": [
                {
                    "changeRequest": {
                        "id": 32,
                        "archive": false,
                        "description": "Cloud files in BlueFunda AI is not working",
                        "shortDescription": "Cloud files not working",
                        "status": "inprogress",
                        "importId": "",
                        "projectId": 28,
                        "releaseId": "",
                        "requestId": "",
                        "requestType": "7454",
                        "requestedBy": "u-100"
                    },
                    "requestId": "CR-1042",
                    "severityData": {"id": 2, "type": "High"},
                    "requestTypeData": {"id": 7454, "type": "Database"},
                    "userTimeline": [
                        {
                            "user": {"name": "Alex Smith"},
                            "timeline": {"fieldName": "Status changed", "createdAt": "2026-01-15T10:30:00Z"}
                        }
                    ]
                }
            ],
            "userProfile": {
                "u-100": {"name": "Jane Doe"}
            }
        }
        """.utf8)

        let response = try RequestsAPIClient.makeDecoder().decode(ChangeRequestListResponse.self, from: json)
        XCTAssertEqual(response.combinedResponse.count, 1)

        let cr = response.combinedResponse[0]
        XCTAssertEqual(cr.id, "32")
        XCTAssertEqual(cr.requestNumber, "CR-1042")
        XCTAssertEqual(cr.title, "Cloud files not working")
        XCTAssertEqual(cr.status, .inProgress)
        XCTAssertEqual(cr.severity, "High")
        XCTAssertEqual(cr.requestTypeLabel, "Database")
        XCTAssertEqual(cr.requestedByUserId, "u-100")
        XCTAssertEqual(cr.timeline.count, 1)
        XCTAssertEqual(cr.timeline[0].userName, "Alex Smith")
        XCTAssertEqual(response.userProfile?["u-100"]?.name, "Jane Doe")
    }

    func testUnknownStatusFallsBackToOtherInsteadOfCrashing() {
        let status = ChangeRequestStatus(raw: "pending_qa")
        if case .other(let raw) = status {
            XCTAssertEqual(raw, "pending_qa")
        } else {
            XCTFail("Expected .other for an unrecognized status")
        }
    }

    func testDecodeComments() throws {
        let json = Data("""
        {
            "comments": [
                {
                    "comment": "<p>Looks good to me</p>",
                    "createdAt": "2026-01-15T10:30:00Z",
                    "user": {"name": "Jane Doe"},
                    "attachments": [{"id": 5, "name": "plan.pdf"}]
                }
            ]
        }
        """.utf8)

        struct Wrapper: Decodable { let comments: [RQComment] }
        let wrapper = try RequestsAPIClient.makeDecoder().decode(Wrapper.self, from: json)

        XCTAssertEqual(wrapper.comments.count, 1)
        let comment = wrapper.comments[0]
        XCTAssertEqual(comment.plainTextBody, "Looks good to me")
        XCTAssertEqual(comment.authorName, "Jane Doe")
        XCTAssertEqual(comment.attachments.first?.fileName, "plan.pdf")
        XCTAssertEqual(comment.attachments.first?.id, "5")
    }

    /// No live sample exists for this one (unlike ChangeRequest) — this is a best-effort
    /// shape from trm's frontend source, so the test only asserts the defensive decode
    /// doesn't crash and pulls what it can, not exact field values against real data.
    func testDecodeReleases() throws {
        let json = Data("""
        {
            "releases": [
                {
                    "changeRequestId": 32,
                    "requestId": "CR-1042",
                    "status": "inprogress",
                    "plannedOn": "2026-01-20T00:00:00Z"
                },
                {
                    "changeRequestId": 31,
                    "status": "unexpectedstatus"
                }
            ]
        }
        """.utf8)

        let response = try RequestsAPIClient.makeDecoder().decode(ReleaseListResponse.self, from: json)
        XCTAssertEqual(response.releases.count, 2)

        let first = response.releases[0]
        XCTAssertEqual(first.changeRequestId, "32")
        XCTAssertEqual(first.requestId, "CR-1042")
        XCTAssertEqual(first.status, .inProgress)
        XCTAssertNotNil(first.plannedOn)

        let second = response.releases[1]
        XCTAssertEqual(second.changeRequestId, "31")
        XCTAssertNil(second.plannedOn)
        if case .other(let raw) = second.status {
            XCTAssertEqual(raw, "unexpectedstatus")
        } else {
            XCTFail("Expected .other for an unrecognized release status")
        }
    }

    func testDecodeUnreadCounts() throws {
        let json = Data("""
        {
            "totalUnreadMessages": 3,
            "perCRUnreadCounts": [{"crNumber": "32", "count": 2}]
        }
        """.utf8)

        let counts = try JSONDecoder().decode(UnreadCounts.self, from: json)
        XCTAssertEqual(counts.totalUnreadMessages, 3)
        XCTAssertEqual(counts.count(forChangeRequestId: "32"), 2)
        XCTAssertEqual(counts.count(forChangeRequestId: "99"), 0)
    }
}
