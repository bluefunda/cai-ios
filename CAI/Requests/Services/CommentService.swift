import Foundation

// MARK: - Comment Service
// View + post — this is the one write path in v1 (see trm-ios plan §06).

protocol CommentServicing {
    func comments(forChangeRequestId id: String) async throws -> [RQComment]
    func postComment(_ body: String, attachments: [RQAttachment], forChangeRequestId id: String) async throws -> RQComment
}

struct CommentService: CommentServicing {
    let client: RequestsAPIClient
    /// Needed for `createdBy` (the Keycloak `sub`) on post, and the display name on the
    /// optimistic local comment appended immediately after.
    let currentUserProvider: @Sendable () async -> User?

    func comments(forChangeRequestId id: String) async throws -> [RQComment] {
        let response: CommentsResponse = try await client.get("/comments/change-request/\(id)")
        return response.comments
    }

    func postComment(_ body: String, attachments: [RQAttachment] = [], forChangeRequestId id: String) async throws -> RQComment {
        guard let user = await currentUserProvider() else { throw RequestsAPIError.notSignedIn }
        guard let changeRequestId = Int(id) else { throw RequestsAPIError.invalidURL }

        let request = NewCommentRequest(
            comment: body,
            createdBy: user.id,
            changeRequestId: changeRequestId,
            attachments: attachments.map { CommentAttachmentRef(id: $0.id, fileName: $0.fileName) }
        )
        try await client.postDiscardingResponse("/comments", body: request)

        // The create endpoint's response shape isn't confirmed (no OpenAPI spec) — construct
        // the comment locally from what's already known rather than guess-decode an
        // uncertain response. A subsequent full reload reconciles with server truth.
        return RQComment(bodyHTML: body, authorName: user.name, createdAt: Date(), attachments: attachments)
    }
}

private struct CommentsResponse: Decodable {
    let comments: [RQComment]
}
