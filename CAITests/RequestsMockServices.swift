// MARK: - BlueRequests Service Mocks
// Ported from trm-ios (TRMTests/MockServices.swift).

@testable import CAI

struct MockChangeRequestService: ChangeRequestServicing {
    var listResult: Result<[ChangeRequest], Error> = .success([])
    var detailResult: Result<ChangeRequest, Error>?

    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] {
        try listResult.get()
    }

    func changeRequest(id: String) async throws -> ChangeRequest {
        try (detailResult ?? listResult.map { $0.first! }).get()
    }

    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest {
        try (detailResult ?? listResult.map { $0.first! }).get()
    }

    func update(_ payload: ChangeRequestUpdatePayload) async throws {}
}

struct MockCommentService: CommentServicing {
    var commentsResult: Result<[RQComment], Error> = .success([])
    var postResult: Result<RQComment, Error>?

    func comments(forChangeRequestId id: String) async throws -> [RQComment] {
        try commentsResult.get()
    }

    func postComment(_ body: String, attachments: [RQAttachment], forChangeRequestId id: String) async throws -> RQComment {
        if let postResult { return try postResult.get() }
        return RQComment(bodyHTML: body, authorName: "Me", createdAt: nil, attachments: attachments)
    }
}
