import Foundation

@MainActor
final class ChangeRequestDetailViewModel: ObservableObject {
    @Published private(set) var changeRequest: ChangeRequest?
    @Published private(set) var comments: [RQComment] = []
    @Published private(set) var crFiles: [CRFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPostingComment = false
    @Published private(set) var isUploadingFile = false
    @Published private(set) var isSaving = false
    @Published var error: String?

    let changeRequestId: String

    private let changeRequestService: ChangeRequestServicing
    private let commentService: CommentServicing
    private let attachmentService: AttachmentServicing
    private let crFileService: CRFileServicing
    private let currentUserId: String?

    init(
        changeRequestId: String,
        changeRequestService: ChangeRequestServicing,
        commentService: CommentServicing,
        attachmentService: AttachmentServicing,
        crFileService: CRFileServicing,
        currentUserId: String?
    ) {
        self.changeRequestId = changeRequestId
        self.changeRequestService = changeRequestService
        self.commentService = commentService
        self.attachmentService = attachmentService
        self.crFileService = crFileService
        self.currentUserId = currentUserId
    }

    /// Comment attachments, flattened — these live on the Postgres `files` store (see
    /// AttachmentService), distinct from `crFiles` below (minio-backed CR Files tab).
    var attachments: [RQAttachment] {
        comments.flatMap(\.attachments)
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let cr = changeRequestService.changeRequest(id: changeRequestId)
            async let commentList = commentService.comments(forChangeRequestId: changeRequestId)
            (changeRequest, comments) = try await (cr, commentList)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        await loadFiles()
    }

    func loadFiles() async {
        guard let projectId = changeRequest?.projectId else { return }
        do {
            crFiles = try await crFileService.list(projectId: projectId, changeRequestId: changeRequestId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func uploadFile(url: URL) async {
        guard let projectId = changeRequest?.projectId else { return }
        isUploadingFile = true
        do {
            let file = try await crFileService.upload(projectId: projectId, changeRequestId: changeRequestId, fileURL: url)
            crFiles.append(file)
        } catch {
            self.error = error.localizedDescription
        }
        isUploadingFile = false
    }

    func postComment(_ body: String, attachments: [RQAttachment] = []) async {
        guard !body.isBlank || !attachments.isEmpty else { return }
        isPostingComment = true
        do {
            let comment = try await commentService.postComment(
                body, attachments: attachments, forChangeRequestId: changeRequestId
            )
            comments.append(comment)
        } catch {
            self.error = error.localizedDescription
        }
        isPostingComment = false
    }

    func uploadCommentAttachment(url: URL) async throws -> RQAttachment {
        try await attachmentService.upload(fileURL: url)
    }

    func downloadCommentAttachment(id: String) async throws -> (data: Data, mimeType: String?, fileName: String) {
        try await attachmentService.download(id: id)
    }

    // MARK: - Edit / Status / Archive
    // All three call the same partial-update endpoint (see ChangeRequestUpdatePayload's doc
    // comment) and refetch afterward to pick up the backend's auto-written timeline entry.

    func applyEdit(
        shortDescription: String?,
        description: String?,
        requestType: String?,
        severity: String?,
        requestedBy: String?,
        ticketUrl: String?
    ) async {
        await performUpdate(ChangeRequestUpdatePayload(
            id: changeRequestId,
            createdBy: currentUserId ?? "",
            updatedBy: currentUserId ?? "",
            shortDescription: shortDescription,
            description: description,
            requestType: requestType,
            severity: severity,
            requestedBy: requestedBy,
            ticketUrl: ticketUrl
        ))
    }

    func setStatus(_ status: ChangeRequestStatus) async {
        await performUpdate(ChangeRequestUpdatePayload(
            id: changeRequestId,
            createdBy: currentUserId ?? "",
            updatedBy: currentUserId ?? "",
            status: status.rawValue
        ))
    }

    func setArchived(_ archived: Bool) async {
        await performUpdate(ChangeRequestUpdatePayload(
            id: changeRequestId,
            createdBy: currentUserId ?? "",
            updatedBy: currentUserId ?? "",
            archive: archived
        ))
    }

    private func performUpdate(_ payload: ChangeRequestUpdatePayload) async {
        isSaving = true
        error = nil
        do {
            try await changeRequestService.update(payload)
            changeRequest = try await changeRequestService.changeRequest(id: changeRequestId)
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
