import Foundation

@MainActor
final class ChangeRequestDetailViewModel: ObservableObject {
    @Published private(set) var changeRequest: ChangeRequest?
    /// Goes up after every saved change (status, archive, edit, stage move, decision), so
    /// the request list can reload: it otherwise keeps its copy until a refresh.
    @Published private(set) var savedChanges = 0
    @Published private(set) var comments: [RQComment] = []
    @Published private(set) var crFiles: [CRFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPostingComment = false
    @Published private(set) var isUploadingFile = false
    @Published private(set) var isSaving = false
    @Published var error: String?
    /// The approval workflow; nil until loaded, or when the endpoint isn't there — both
    /// mean the legacy stage buttons, as on the web.
    @Published private(set) var workflow: RQWorkflow?
    @Published private(set) var isMovingStage = false
    @Published private(set) var isDeciding = false
    /// The project's people, minus you — who the comment box offers to @mention.
    @Published private(set) var mentionCandidates: [ProjectTeamMember] = []

    let changeRequestId: String

    private let changeRequestService: ChangeRequestServicing
    private let workflowService: ChangeRequestWorkflowServicing
    private let commentService: CommentServicing
    private let attachmentService: AttachmentServicing
    private let crFileService: CRFileServicing
    private let currentUserId: String?

    init(
        changeRequestId: String,
        changeRequestService: ChangeRequestServicing,
        workflowService: ChangeRequestWorkflowServicing,
        commentService: CommentServicing,
        attachmentService: AttachmentServicing,
        crFileService: CRFileServicing,
        currentUserId: String?
    ) {
        self.changeRequestId = changeRequestId
        self.changeRequestService = changeRequestService
        self.workflowService = workflowService
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
        async let files: Void = loadFiles()
        async let steps: Void = loadWorkflow()
        async let people: Void = loadMentionCandidates()
        _ = await (files, steps, people)
    }

    func loadMentionCandidates() async {
        guard let projectId = changeRequest?.projectId,
              let people = try? await commentService.mentionCandidates(projectId: projectId) else { return }
        mentionCandidates = people.filter { $0.id != currentUserId }
    }

    /// Clears your unread comment count for this request, as opening the web's Comments
    /// tab does. Best effort: a failure changes nothing on screen.
    func markCommentsSeen() async {
        guard let currentUserId else { return }
        try? await commentService.markSeen(changeRequestId: changeRequestId, userId: currentUserId)
    }

    func loadWorkflow() async {
        workflow = try? await workflowService.workflow(changeRequestId: changeRequestId)
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

    /// Removes a file from the Files tab, as the web's delete icon does.
    func deleteFile(_ file: CRFile) async {
        guard let projectId = changeRequest?.projectId else { return }
        do {
            try await crFileService.delete(projectId: projectId, changeRequestId: changeRequestId, fileName: file.name)
            crFiles.removeAll { $0.id == file.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// People @mentioned in `body` (typed as "@Name" from `mentionCandidates`) are linked
    /// and notified the way the web's comment box does it.
    func postComment(_ body: String, attachments: [RQAttachment] = []) async {
        guard !body.isBlank || !attachments.isEmpty else { return }
        isPostingComment = true
        let mentioned = CommentComposition.mentions(in: body, from: mentionCandidates)
        do {
            let comment = try await commentService.postComment(
                CommentComposition.body(for: body, mentioning: mentioned), attachments: attachments,
                mentions: mentioned.map(\.id), forChangeRequestId: changeRequestId
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

    /// True once deleted, so the screen can close; on failure `error` is set and the
    /// request stays on screen.
    @discardableResult
    func delete() async -> Bool {
        guard let userId = currentUserId else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await changeRequestService.delete(id: changeRequestId, updatedBy: userId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - Stage Flow / Approvals

    var isWorkflowEnforced: Bool { workflow?.enforced == true }

    var stageActions: StageActions {
        changeRequest?.stageActions(workflowEnforced: isWorkflowEnforced) ?? .none
    }

    /// The web's push drawer: the optional comment is posted first, then the stage moves,
    /// then the status follows it. True once moved, so the sheet can close.
    @discardableResult
    func moveStage(_ move: StageMove, comment: String) async -> Bool {
        guard let userId = currentUserId, let numericId = Int(changeRequestId),
              let total = changeRequest?.stages.count, !move.needsWeb else { return false }
        isMovingStage = true
        error = nil
        defer { isMovingStage = false }
        do {
            if !comment.isBlank {
                let posted = try await commentService.postComment(comment, attachments: [], forChangeRequestId: changeRequestId)
                comments.append(posted)
            }
            try await workflowService.moveStage(StageUpdatePayload(
                move: move, changeRequestId: numericId, updatedBy: userId, totalStages: total))
            try await changeRequestService.update(ChangeRequestUpdatePayload(
                id: changeRequestId, createdBy: userId, updatedBy: userId, status: move.status.rawValue))
            savedChanges += 1
            changeRequest = try await changeRequestService.changeRequest(id: changeRequestId)
            return true
        } catch {
            self.error = error.localizedDescription
            // Whatever did land (the comment, or the stage without its status) shows up.
            if let refreshed = try? await changeRequestService.changeRequest(id: changeRequestId) {
                changeRequest = refreshed
            }
            return false
        }
    }

    /// Approve or reject the current step. On a refusal that means the step moved on,
    /// the workflow is reloaded so the screen shows the server's view. Returns the error
    /// message to show, or nil on success.
    func decide(_ decision: WorkflowDecision, on step: RQWorkflowStep, comment: String) async -> String? {
        isDeciding = true
        defer { isDeciding = false }
        do {
            try await workflowService.decide(
                changeRequestId: changeRequestId, order: step.order,
                WorkflowDecisionPayload(decision: decision, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            if WorkflowDecisionError.needsRefresh(error) { await loadWorkflow() }
            return WorkflowDecisionError.message(for: error)
        }
        savedChanges += 1
        await loadWorkflow()
        if let refreshed = try? await changeRequestService.changeRequest(id: changeRequestId) {
            changeRequest = refreshed
        }
        return nil
    }

    private func performUpdate(_ payload: ChangeRequestUpdatePayload) async {
        isSaving = true
        error = nil
        do {
            try await changeRequestService.update(payload)
            savedChanges += 1
            changeRequest = try await changeRequestService.changeRequest(id: changeRequestId)
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
