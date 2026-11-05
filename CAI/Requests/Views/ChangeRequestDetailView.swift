import SwiftUI
import UniformTypeIdentifiers

// MARK: - Change Request Detail
// Ported from trm-ios and reshaped to P6: a header card (number, title, status pill,
// full stage rail), then a segmented control — Details, Activity, Comments, Files.
// Edit and Archive live in a `···` menu; archiving asks first.

struct ChangeRequestDetailView: View {
    let changeRequestId: String
    @ObservedObject var state: RequestsState

    @StateObject private var box = ViewModelBox()

    var body: some View {
        Group {
            if let model = box.model {
                DetailBody(model: model, state: state)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BFColor.surfaceCanvas)
        .task {
            guard let services = state.services, box.model == nil else { return }
            let model = ChangeRequestDetailViewModel(
                changeRequestId: changeRequestId,
                changeRequestService: services.changeRequestService,
                commentService: services.commentService,
                attachmentService: services.attachmentService,
                crFileService: services.crFileService,
                currentUserId: state.currentUserId
            )
            box.model = model
            await model.load()
        }
    }

    private final class ViewModelBox: ObservableObject {
        @Published var model: ChangeRequestDetailViewModel?
    }
}

enum ChangeRequestDetailTab: String, CaseIterable, Identifiable {
    case details, activity, comments, files
    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "Details"
        case .activity: return "Activity"
        case .comments: return "Comments"
        case .files: return "Files"
        }
    }
}

private struct DetailBody: View {
    @ObservedObject var model: ChangeRequestDetailViewModel
    @ObservedObject var state: RequestsState

    @State private var selectedTab: ChangeRequestDetailTab = .details
    @State private var showEditSheet = false
    @State private var confirmArchive = false

    var body: some View {
        content
            // Empty but present (the back button needs the bar): the header card already
            // shows the request number, and a second copy here would just repeat it.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let cr = model.changeRequest {
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
            .onChange(of: model.changeRequest) { _, changeRequest in
                if let changeRequest { state.recents.record(changeRequest) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let cr = model.changeRequest {
            VStack(spacing: 0) {
                DetailHeaderCard(changeRequest: cr, isSaving: model.isSaving) { status in
                    Task { await model.setStatus(status) }
                }

                if let error = model.error {
                    InlineErrorBanner(message: error) {
                        model.error = nil
                        Task { await model.load() }
                    }
                    .padding(.horizontal, BFSpacing._4)
                }

                Picker("Section", selection: $selectedTab) {
                    ForEach(ChangeRequestDetailTab.allCases) { tab in
                        Text(tabTitle(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, BFSpacing._4)
                .padding(.vertical, BFSpacing._2)
                .accessibilityIdentifier("requests.detail.tabs")

                BFHairline()

                Group {
                    switch selectedTab {
                    case .details: DetailsTab(changeRequest: cr)
                    case .activity: ActivityTab(changeRequest: cr)
                    case .comments: CommentThreadView(model: model)
                    case .files: FilesTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
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
        default: return tab.title
        }
    }

    private func moreMenu(_ cr: ChangeRequest) -> some View {
        Menu {
            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
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
/// the generic PUT endpoint, not the full stage-progression flow (out of scope).
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
        .disabled(isSaving)
        .bfPointerHover()
        .accessibilityLabel("Status: \(status.style.label). Change status")
        .accessibilityIdentifier("requests.detail.status")
    }
}

// MARK: - Details

private struct DetailsTab: View {
    let changeRequest: ChangeRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BFSpacing._4) {
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
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var platformSummary: String? {
        let systems = changeRequest.platforms.compactMap(\.sap).filter { !$0.isBlank }
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
                .frame(maxWidth: 720, alignment: .leading)
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
                    if let url = URL(string: file.url) {
                        Link(destination: url) { FileRow(file: file) }
                            .bfPointerHover()
                    } else {
                        FileRow(file: file)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                await model.uploadFile(url: url)
            }
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
