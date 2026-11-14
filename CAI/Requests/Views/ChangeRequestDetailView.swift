import SwiftUI
import UniformTypeIdentifiers

// MARK: - Change Request Detail
// Ported from trm-ios and reshaped to P6: a header card (number, title, status pill,
// full stage rail), then a segmented control — Details, Activity, Comments, Files, AI and,
// for a tech-template request, GitHub (its linked issues, trm's changeRequestGitHubIssues).
// Edit and Archive live in a `···` menu; archiving asks first. The stage buttons (or, when
// the tenant enforces it, the approval workflow) follow the web's detail screen.

struct ChangeRequestDetailView: View {
    let changeRequestId: String
    @ObservedObject var state: RequestsState
    /// Which stack it was pushed on: back (and after a delete) returns there.
    var origin: RequestDetailOrigin = .requests

    @StateObject private var box = ViewModelBox()

    var body: some View {
        Group {
            if let model = box.model {
                DetailBody(model: model, state: state, origin: origin)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BFColor.surfaceCanvas)
        .task {
            guard let services = state.services else { return }
            if box.model == nil {
                box.model = ChangeRequestDetailViewModel(
                    changeRequestId: changeRequestId,
                    changeRequestService: services.changeRequestService,
                    workflowService: services.workflowService,
                    commentService: services.commentService,
                    attachmentService: services.attachmentService,
                    crFileService: services.crFileService,
                    currentUserId: state.currentUserId
                )
            }
            // Loads again if an earlier load was cut short, so the tabs never stay empty.
            if let model = box.model, !model.hasLoaded { await model.load() }
        }
    }

    private final class ViewModelBox: ObservableObject {
        @Published var model: ChangeRequestDetailViewModel?
    }
}

enum ChangeRequestDetailTab: String, CaseIterable, Identifiable {
    case details, activity, comments, files, ai, github
    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "Details"
        case .activity: return "Activity"
        case .comments: return "Comments"
        case .files: return "Files"
        case .ai: return "AI"
        case .github: return "GitHub"
        }
    }
}

private struct DetailBody: View {
    @ObservedObject var model: ChangeRequestDetailViewModel
    @ObservedObject var state: RequestsState
    let origin: RequestDetailOrigin

    @State private var selectedTab: ChangeRequestDetailTab = .details
    @State private var showEditSheet = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var pendingMove: StageMove?
    @Environment(\.dismiss) private var dismiss
    /// Ask AI and the AI tab (P8) — nil where the shell can't reach the Assistant space.
    @Environment(\.requestBridge) private var requestBridge
    @Environment(\.requestChatLinks) private var requestChatLinks
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var tabs: [ChangeRequestDetailTab] {
        ChangeRequestDetailTab.allCases.filter { tab in
            switch tab {
            case .ai: return requestBridge != nil
            // Only requests from a tech template have GitHub issues.
            case .github: return GitHubIntegration.isTechRequest(model.changeRequest)
            default: return true
            }
        }
    }

    var body: some View {
        content
            // Empty but present (the back button needs the bar): the header card already
            // shows the request number, and a second copy here would just repeat it.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let cr = model.changeRequest {
                    if let requestBridge {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                requestBridge.askAI(cr)
                            } label: {
                                Label("Ask AI", systemImage: "sparkles")
                            }
                            .help("Ask AI about this request")
                            .bfPointerHover()
                            .accessibilityIdentifier("requests.detail.askAI")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        moreMenu(cr)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let cr = model.changeRequest {
                    EditChangeRequestView(changeRequest: cr, model: model, services: state.services)
                }
            }
            .confirmationDialog(
                "Archive this request?",
                isPresented: $confirmArchive,
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    Task { await model.setArchived(true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It moves to the Archive tab. You can unarchive it from there.")
            }
            .confirmationDialog(
                "Delete this request?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        let wasArchived = model.changeRequest?.isArchived == true
                        if await model.delete() {
                            // Back where it was opened from (a project pops back to it);
                            // an archived request's list opens on Archive.
                            dismiss()
                            await state.didDeleteRequest(
                                id: model.changeRequestId, wasArchived: wasArchived, origin: origin)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                // The web's wording (changeRequestDetail.js).
                Text("This removes the request and its transfer info from the database. It can't be undone.")
            }
            .sheet(item: $pendingMove) { move in
                StageMoveSheet(move: move, model: model)
            }
            .onChange(of: model.changeRequest) { _, changeRequest in
                if let changeRequest { state.recents.record(changeRequest) }
            }
            // Unarchive, status, edits and stage moves show in the list (and the right
            // Active/Archive tab) without a refresh.
            .onChange(of: model.savedChanges) { _, _ in
                state.requestsChanged += 1
                Task { await state.changeRequests?.load() }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .comments { Task { await model.markCommentsSeen() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let cr = model.changeRequest {
            VStack(spacing: 0) {
                DetailHeaderCard(
                    changeRequest: cr,
                    isSaving: model.isSaving || model.isMovingStage,
                    stageActions: model.stageActions,
                    onMove: { pendingMove = $0 }
                ) { status in
                    Task { await model.setStatus(status) }
                }

                if let error = model.error {
                    // Retry repeats a failed file upload or delete, else reloads.
                    InlineErrorBanner(message: error, onRetry: {
                        Task { await model.retryAfterError() }
                    }, onDismiss: model.dismissError)
                    .padding(.horizontal, BFSpacing._4)
                }

                // New request hands over why its GitHub issue wasn't created (the request was).
                if let notice = state.githubIssueNotices[model.changeRequestId] {
                    DismissableNotice(message: notice) {
                        state.githubIssueNotices[model.changeRequestId] = nil
                    }
                    .padding(.horizontal, BFSpacing._4)
                    .padding(.bottom, BFSpacing._2)
                    .accessibilityIdentifier("requests.detail.githubNotice")
                }

                // Five tabs don't fit a segmented control on an iPhone ("Comments" was cut
                // off), so compact width scrolls a row of tabs instead.
                if sizeClass == .compact {
                    DetailTabStrip(tabs: tabs, selection: $selectedTab, title: tabTitle)
                        .accessibilityIdentifier("requests.detail.tabs")
                } else {
                    Picker("Section", selection: $selectedTab) {
                        ForEach(tabs) { tab in
                            Text(tabTitle(tab)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, BFSpacing._4)
                    .padding(.vertical, BFSpacing._2)
                    .accessibilityIdentifier("requests.detail.tabs")
                }

                BFHairline()

                Group {
                    switch selectedTab {
                    case .details: DetailsTab(changeRequest: cr, model: model)
                    case .activity: ActivityTab(changeRequest: cr)
                    case .comments: CommentThreadView(model: model)
                    case .files: FilesTab(model: model)
                    case .ai: AITab(changeRequest: cr, links: requestChatLinks, bridge: requestBridge)
                    case .github:
                        if let services = state.services, GitHubIntegration.isTechRequest(cr) {
                            GitHubIssuesTab(model: GitHubIssuesViewModel(
                                changeRequestId: cr.id,
                                projectId: cr.projectId,
                                defaultTitle: cr.title,
                                service: services.githubService,
                                users: { try await services.referenceDataService.users(forceRefresh: false) }
                            ), state: state)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // The header, tabs and tab content use the window's full width.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RequestsErrorCard(message: RequestsErrorCard.message(for: model.error, subject: "this request")) {
                model.error = nil
                Task { await model.load() }
            }
        }
    }

    private func tabTitle(_ tab: ChangeRequestDetailTab) -> String {
        switch tab {
        case .comments: return model.comments.isEmpty ? tab.title : "\(tab.title) \(model.comments.count)"
        case .files: return model.crFiles.isEmpty ? tab.title : "\(tab.title) \(model.crFiles.count)"
        case .ai:
            let count = requestChatLinks?.conversations(forRequest: model.changeRequestId).count ?? 0
            return count == 0 ? tab.title : "\(tab.title) \(count)"
        default: return tab.title
        }
    }

    private func moreMenu(_ cr: ChangeRequest) -> some View {
        Menu {
            // As on the web: editing is only for a request still at its first stage;
            // deleting too, or once it's archived (`canDelete`).
            if cr.isAtFirstStage {
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if cr.isArchived {
                Button {
                    Task { await model.setArchived(false) }
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button(role: .destructive) {
                    confirmArchive = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            if cr.canDelete {
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(model.isSaving)
        .bfPointerHover()
        .accessibilityIdentifier("requests.detail.more")
    }
}

// MARK: - Header Card

private struct DetailHeaderCard: View {
    let changeRequest: ChangeRequest
    let isSaving: Bool
    let stageActions: StageActions
    let onMove: (StageMove) -> Void
    let onSetStatus: (ChangeRequestStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(changeRequest.requestNumber)
                    .font(RQFont.number)
                    .foregroundStyle(.secondary)
                if changeRequest.isArchived {
                    Text("Archived")
                        .font(RQFont.pill)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                StatusMenu(status: changeRequest.status, isSaving: isSaving, onSelect: onSetStatus)
            }

            Text(changeRequest.title)
                .font(BFFont.h5)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            StageRail(
                stage: changeRequest.stage,
                totalStages: changeRequest.totalStages,
                status: changeRequest.status,
                stageStatus: changeRequest.stageStatus,
                size: .full
            )

            if stageActions != .none {
                StageActionBar(actions: stageActions, isBusy: isSaving, onMove: onMove)
            }
        }
        .padding(BFSpacing._4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous)
                .strokeBorder(BFColor.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, BFSpacing._4)
        .padding(.top, BFSpacing._3)
        .padding(.bottom, BFSpacing._2)
    }
}

/// Direct status change — the same plain status update trm web's Kanban drag makes on
/// the generic PUT endpoint. Moving between stages is the StageActionBar below.
private struct StatusMenu: View {
    let status: ChangeRequestStatus
    let isSaving: Bool
    let onSelect: (ChangeRequestStatus) -> Void

    var body: some View {
        Menu {
            ForEach(ChangeRequestStatus.allCases, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == status {
                        Label(option.style.label, systemImage: "checkmark")
                    } else {
                        Text(option.style.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                StatusPill(status: status)
                if isSaving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Drawn as written: a Mac otherwise redraws the label as a pull-down button,
        // dropping the pill and adding a second chevron.
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(isSaving)
        .bfPointerHover()
        .accessibilityLabel("Status: \(status.style.label). Change status")
        .accessibilityIdentifier("requests.detail.status")
    }
}

// MARK: - Details

private struct DetailsTab: View {
    let changeRequest: ChangeRequest
    @ObservedObject var model: ChangeRequestDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BFSpacing._4) {
                if let workflow = model.workflow, workflow.enforced, !workflow.steps.isEmpty {
                    WorkflowSection(workflow: workflow, model: model)
                }

                if let description = changeRequest.description, !description.isBlank {
                    VStack(alignment: .leading, spacing: 6) {
                        RQFieldLabel("Description")
                        Text(description)
                            .font(RQFont.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }

                VStack(spacing: 0) {
                    if let severity = changeRequest.severity, !severity.isBlank {
                        field("Priority") { PriorityPill(text: severity) }
                    }
                    if let type = changeRequest.requestTypeLabel, !type.isBlank {
                        field("Type") { valueText(type) }
                    }
                    if let project = changeRequest.projectName, !project.isBlank {
                        field("Project") { valueText(project) }
                    }
                    field("Platform") { valueText(platformSummary ?? "None") }
                    if let owner = changeRequest.currentStageOwnerName {
                        field("Stage owner") { valueText(owner) }
                    }
                    if let ticket = changeRequest.ticketUrl, !ticket.isBlank {
                        field("Ticket") {
                            if let url = URL(string: ticket), url.scheme != nil {
                                Link(ticket, destination: url).font(RQFont.body).lineLimit(1)
                            } else {
                                valueText(ticket)
                            }
                        }
                    }
                    field("Requested by") {
                        OwnerBadge(name: changeRequest.createdByName, avatarURLString: changeRequest.createdByAvatarURL)
                    }
                    if let date = changeRequest.submittedAt {
                        field("Submitted") {
                            valueText(date.formatted(date: .abbreviated, time: .omitted))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(BFSpacing._4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var platformSummary: String? {
        let systems = changeRequest.platforms.compactMap(\.description).filter { !$0.isBlank }
        return systems.isEmpty ? nil : systems.joined(separator: ", ")
    }

    private func valueText(_ text: String) -> Text {
        Text(text).font(RQFont.body).foregroundColor(.primary)
    }

    private func field<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BFSpacing._3) {
            RQFieldLabel(label)
                .frame(width: 110, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { BFHairline() }
    }
}

// MARK: - Activity

private struct ActivityTab: View {
    let changeRequest: ChangeRequest

    var body: some View {
        // Newest first — matches trm web's own timeline ordering.
        let entries = changeRequest.timeline
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        if entries.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "clock")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TimelineRow(entry: entry, isLast: index == entries.count - 1)
                    }
                }
                .padding(BFSpacing._4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "{user} {action}" on one line, the date under it. The dot takes the status colour
/// when the entry moved the status, so the timeline reads like the board (P6).
private struct TimelineRow: View {
    let entry: ChangeRequestTimelineEntry
    let isLast: Bool

    private var dotColor: Color {
        guard entry.fieldName == "status", let to = entry.toStatus else { return BFColor.neutral400 }
        return ChangeRequestStatus(raw: to).style.mark
    }

    var body: some View {
        HStack(alignment: .top, spacing: BFSpacing._3) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(BFColor.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 9)

            VStack(alignment: .leading, spacing: 3) {
                (
                    Text(entry.userName ?? "Someone").fontWeight(.semibold)
                        + Text(" \(entry.actionVerb)")
                        + Text(entry.actionDetail.map { " \($0)" } ?? "")
                )
                .font(RQFont.body)
                .foregroundStyle(.primary)

                if let date = entry.createdAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(RQFont.meta)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, BFSpacing._4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Files
// CR-level files — minio-backed (CRFileService), distinct from the comment attachments
// in the Comments tab. `url` is a pre-signed link, openable directly with no auth header,
// the same way trm web's download link works.

private struct FilesTab: View {
    @ObservedObject var model: ChangeRequestDetailViewModel
    @State private var showFileImporter = false
    @State private var pendingDelete: CRFile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showFileImporter = true
                } label: {
                    Label(model.isUploadingFile ? "Uploading…" : "Upload file", systemImage: "arrow.up.doc")
                        .font(RQFont.body)
                }
                .disabled(model.isUploadingFile || model.changeRequest?.projectId == nil)
                .bfPointerHover()
                .accessibilityIdentifier("requests.detail.uploadFile")
            }
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._2)

            if model.crFiles.isEmpty {
                ContentUnavailableView {
                    Label("No files yet", systemImage: "paperclip")
                } actions: {
                    Button("Upload file") { showFileImporter = true }
                        .disabled(model.isUploadingFile || model.changeRequest?.projectId == nil)
                        .bfPointerHover()
                }
            } else {
                List(model.crFiles) { file in
                    HStack(spacing: BFSpacing._2) {
                        if let url = URL(string: file.url) {
                            Link(destination: url) { FileRow(file: file) }
                                .bfPointerHover()
                        } else {
                            FileRow(file: file)
                        }
                        // Visible, as on Android and the web; swipe and long-press still work.
                        Button { pendingDelete = file } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(BFColor.errorDelete)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(file.name)")
                        .bfPointerHover()
                        .accessibilityIdentifier("requests.detail.deleteFile")
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = file }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = file }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this file")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let file = pendingDelete else { return }
                Task { await model.deleteFile(file) }
            }
        } message: {
            Text("It's removed from the request for everyone.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            // The model opens the file's security scope, so its Retry can read it again.
            Task { await model.uploadFile(url: url) }
        }
    }
}

private struct FileRow: View {
    let file: CRFile

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(RQFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let uploader = file.uploaderName, !uploader.isBlank {
                    Text("Uploaded by \(uploader)")
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let size = file.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(RQFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stage Flow

extension StageMove: Identifiable {
    var id: String { "\(kind)-\(from.order)-\(to.order)" }
}

/// The web's stage buttons under the header: Revert, and Start / Push to next stage /
/// Mark as completed. A Deploy to QA the app can't run yet stays visible but disabled,
/// with where to do it instead.
private struct StageActionBar: View {
    let actions: StageActions
    let isBusy: Bool
    let onMove: (StageMove) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: BFSpacing._2) {
                if let revert = actions.revert {
                    Button {
                        onMove(revert)
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("requests.detail.stage.revert")
                }
                if let forward = actions.forward {
                    Button {
                        onMove(forward)
                    } label: {
                        Label(forwardTitle(forward), systemImage: forward.kind == .complete ? "checkmark" : "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(forward.needsWeb)
                    .accessibilityIdentifier("requests.detail.stage.forward")
                }
                if isBusy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .tint(BFColor.primary)
            .disabled(isBusy)

            if let forward = actions.forward, forward.needsWeb {
                Text(forward.kind == .complete && !forward.from.qaDeploy
                     ? "Completing an SAP request releases its transports. Do this from the web app for now."
                     : "Deploy to QA runs SAP transports or a Git merge. Do this from the web app for now.")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func forwardTitle(_ move: StageMove) -> String {
        move.needsWeb && move.from.qaDeploy ? "Deploy to QA" : move.kind.title
    }
}

/// The web's push drawer: where the request is and where it's going, an optional comment
/// that's posted with the move, then confirm.
private struct StageMoveSheet: View {
    let move: StageMove
    @ObservedObject var model: ChangeRequestDetailViewModel

    @State private var comment = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    stageRow(label: move.kind == .revert ? "From" : "Current stage", stage: move.from,
                             owner: model.changeRequest?.currentStageOwnerName)
                    stageRow(label: move.kind == .revert ? "Back to" : "Next stage", stage: move.to, owner: nil)
                } footer: {
                    Text("The request will be \(move.status.style.label.lowercased()) after this.")
                }

                Section("Comment") {
                    TextField("Add a note for the team (optional)", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("requests.stageMove.comment")
                        .formMultilineField()
                }

                if let error = model.error {
                    Section {
                        Text(error).foregroundStyle(.red).font(RQFont.meta)
                    }
                }
            }
            .navigationTitle(move.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isMovingStage)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isMovingStage {
                        ProgressView()
                    } else {
                        Button(move.kind.title) {
                            Task {
                                if await model.moveStage(move, comment: comment) { dismiss() }
                            }
                        }
                        .accessibilityIdentifier("requests.stageMove.confirm")
                    }
                }
            }
            .interactiveDismissDisabled(model.isMovingStage)
        }
        .presentationDetents([.medium, .large])
        .onAppear { model.error = nil }
    }

    private func stageRow(label: String, stage: RQStage, owner: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            RQFieldLabel(label)
            Text("\(stage.order). \(stage.description.isEmpty ? stage.statusCode : stage.description)")
                .font(RQFont.rowTitle)
            if let owner {
                Text("Owner: \(owner)").font(RQFont.meta).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Approval Workflow

/// The web's ChangeRequestWorkflow: each step with its state, approver, gate and
/// decisions, and Approve/Reject on the current approval step.
private struct WorkflowSection: View {
    let workflow: RQWorkflow
    @ObservedObject var model: ChangeRequestDetailViewModel

    @State private var pending: PendingDecision?
    @State private var decisionError: String?

    struct PendingDecision: Identifiable {
        let step: RQWorkflowStep
        let decision: WorkflowDecision
        var id: String { "\(step.order)-\(decision.rawValue)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            RQFieldLabel("Approval workflow")
            VStack(spacing: 0) {
                ForEach(workflow.steps) { step in
                    stepRow(step)
                    if step.id != workflow.steps.last?.id { BFHairline() }
                }
            }
            .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BFRadius.xl2, style: .continuous)
                    .strokeBorder(BFColor.hairline, lineWidth: 0.5)
            )
            if let decisionError {
                InlineErrorBanner(message: decisionError) { self.decisionError = nil }
            }
        }
        .sheet(item: $pending) { pending in
            WorkflowDecisionSheet(step: pending.step, decision: pending.decision, model: model) { error in
                decisionError = error
            }
        }
    }

    private func stepRow(_ step: RQWorkflowStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(step.order)").font(RQFont.number).foregroundStyle(.secondary)
                Text(step.title).font(RQFont.rowTitle)
                badge(step.stateLabel, color: stateColor(step.state))
                if step.isGate { badge("GitHub gate", color: BFColor.neutral400) }
                Spacer(minLength: 0)
            }
            let approver = [step.department, step.role].filter { !$0.isEmpty }.joined(separator: " · ")
            if !step.isGate, !approver.isEmpty {
                Text(approver).font(RQFont.meta).foregroundStyle(.secondary)
            }
            if step.isGate {
                Text([step.gateLabel, step.gate?.prs.map { $0 == 1 ? "1 pull request" : "\($0) pull requests" },
                      step.state == "satisfied" ? nil : "Waiting for GitHub"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(RQFont.meta).foregroundStyle(.secondary)
            }
            ForEach(step.decisions) { decision in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(decision.actorName).font(RQFont.meta.weight(.semibold))
                        badge(decision.isRejection ? "Rejected" : "Approved",
                              color: decision.isRejection ? .red : .green)
                        if let date = decision.createdAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(RQFont.meta).foregroundStyle(.tertiary)
                        }
                    }
                    if let comment = decision.comment, !comment.isBlank {
                        Text(comment).font(RQFont.meta).foregroundStyle(.secondary)
                    }
                }
            }
            if step.canDecide {
                HStack(spacing: BFSpacing._2) {
                    Button("Reject") { pending = PendingDecision(step: step, decision: .reject) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("requests.workflow.reject")
                    Button("Approve") { pending = PendingDecision(step: step, decision: .approve) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("requests.workflow.approve")
                }
                .controlSize(.small)
                .tint(BFColor.primary)
                .disabled(model.isDeciding)
            } else if step.isAwaitingDecision {
                Text("Waiting for \(approverDescription(step)) to approve")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("requests.workflow.waiting")
            }
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Who can decide a step, for someone who can't: its owner, or its department · role.
    private func approverDescription(_ step: RQWorkflowStep) -> String {
        let group = [step.department, step.role].filter { !$0.isBlank }.joined(separator: " · ")
        // The waiting step is the current one, whose owner's name the request carries.
        let owner = step.owner.flatMap { id -> String? in
            guard let cr = model.changeRequest, cr.currentStage?.ownerId == id else { return nil }
            return cr.currentStageOwnerName
        }
        switch (owner, group.isEmpty) {
        case let (owner?, false): return "\(owner) or \(group)"
        case let (owner?, true): return owner
        case (nil, false): return group
        case (nil, true): return "an approver"
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(RQFont.pill)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "current": return BFColor.primary
        case "approved", "satisfied": return .green
        case "rejected": return .red
        case "blocked": return .orange
        default: return BFColor.neutral400
        }
    }
}

private struct WorkflowDecisionSheet: View {
    let step: RQWorkflowStep
    let decision: WorkflowDecision
    @ObservedObject var model: ChangeRequestDetailViewModel
    let onFailure: (String) -> Void

    @State private var comment = ""
    @Environment(\.dismiss) private var dismiss

    private var verb: String { decision == .approve ? "Approve" : "Reject" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Comment") {
                    TextField(decision == .approve ? "Optional comment" : "Why is this being rejected?",
                              text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("requests.workflow.comment")
                        .formMultilineField()
                }
            }
            .navigationTitle("\(verb) \(step.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.isDeciding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isDeciding {
                        ProgressView()
                    } else {
                        Button(verb) {
                            Task {
                                // As on the web, the sheet closes either way; a refusal
                                // shows under the workflow.
                                if let error = await model.decide(decision, on: step, comment: comment) {
                                    onFailure(error)
                                }
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("requests.workflow.confirm")
                    }
                }
            }
            .interactiveDismissDisabled(model.isDeciding)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AI Tab
// The request's linked chats (started with Ask AI, or turned into this request with
// Create change request…), newest first; tap one to open it in the Assistant space.

private struct AITab: View {
    let changeRequest: ChangeRequest
    let links: RequestChatLinks?
    let bridge: RequestBridgeActions?

    private var chats: [RequestChatLink] { links?.conversations(forRequest: changeRequest.id) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    bridge?.askAI(changeRequest)
                } label: {
                    Label("New chat about this request", systemImage: "sparkles")
                        .font(RQFont.body)
                }
                .disabled(bridge == nil)
                .bfPointerHover()
                .accessibilityIdentifier("requests.detail.newChat")
            }
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._2)

            if chats.isEmpty {
                ContentUnavailableView {
                    Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Ask the assistant about this request, and the chat shows up here.")
                }
            } else {
                List(chats) { chat in
                    Button {
                        bridge?.openConversation(chat)
                    } label: {
                        HStack(spacing: BFSpacing._3) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bridge?.chatTitle(chat.conversationId) ?? "Chat about \(chat.number)")
                                    .font(RQFont.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(chat.linkedAt.formatted(.relative(presentation: .named)))
                                    .font(RQFont.meta)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .bfPointerHover()
                    .swipeActions {
                        Button("Unlink", role: .destructive) { links?.unlink(conversationId: chat.conversationId) }
                    }
                    .accessibilityIdentifier("requests.detail.linkedChat")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// The detail tabs as a scrolling row, for compact width.
private struct DetailTabStrip: View {
    let tabs: [ChangeRequestDetailTab]
    @Binding var selection: ChangeRequestDetailTab
    let title: (ChangeRequestDetailTab) -> String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BFSpacing._2) {
                    ForEach(tabs) { tab in
                        let isSelected = tab == selection
                        Button {
                            selection = tab
                            withAnimation { proxy.scrollTo(tab, anchor: .center) }
                        } label: {
                            Text(title(tab))
                                .font(RQFont.body.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .padding(.horizontal, BFSpacing._3)
                                .padding(.vertical, 6)
                                .background(isSelected ? BFColor.surfaceSunken : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("requests.detail.tab.\(tab.rawValue)")
                    }
                }
                .padding(.horizontal, BFSpacing._4)
                .padding(.vertical, BFSpacing._2)
            }
        }
    }
}
