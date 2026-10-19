import SwiftUI
import UniformTypeIdentifiers

/// Ported from trm-ios: the comment list with a composer pinned underneath, comment
/// attachments upload before posting. Restyled with cai's adaptive surfaces.
struct CommentThreadView: View {
    @ObservedObject var model: ChangeRequestDetailViewModel
    @State private var draft = ""
    @State private var pendingAttachments: [RQAttachment] = []
    @State private var isUploadingAttachment = false
    @State private var showFileImporter = false
    @State private var uploadError: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BFSpacing._3) {
                    if model.comments.isEmpty {
                        Text("No comments yet. Start the conversation below.")
                            .font(RQFont.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, BFSpacing._6)
                    } else {
                        ForEach(model.comments) { comment in
                            CommentRow(comment: comment, model: model)
                        }
                    }
                }
                .padding(BFSpacing._4)
            }

            BFHairline()
            VStack(alignment: .leading, spacing: BFSpacing._2) {
                if !pendingAttachments.isEmpty {
                    pendingAttachmentChips
                }
                composer
            }
            .padding(BFSpacing._3)
            .background(BFColor.surfaceCanvas)
        }
        .alert("Couldn't attach that file", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
    }

    private var pendingAttachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BFSpacing._2) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text(attachment.fileName)
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(RQFont.meta)
                    .padding(.horizontal, BFSpacing._2)
                    .padding(.vertical, 4)
                    .background(BFColor.surfaceSunken, in: Capsule())
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: BFSpacing._2) {
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .disabled(isUploadingAttachment)
            .accessibilityLabel("Attach a file")
            .bfPointerHover()
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    isUploadingAttachment = true
                    do {
                        let attachment = try await model.uploadCommentAttachment(url: url)
                        pendingAttachments.append(attachment)
                    } catch {
                        uploadError = error.localizedDescription
                    }
                    isUploadingAttachment = false
                }
            }

            TextField("Add a comment", text: $draft, axis: .vertical)
                .font(RQFont.body)
                .lineLimit(1...5)
                .padding(.horizontal, BFSpacing._3)
                .padding(.vertical, BFSpacing._2)
                .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
                .focused($isComposerFocused)
                .accessibilityIdentifier("requests.comment.field")

            Button {
                let text = draft
                let attachments = pendingAttachments
                draft = ""
                pendingAttachments = []
                isComposerFocused = false
                Task { await model.postComment(text, attachments: attachments) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        draft.isBlank && pendingAttachments.isEmpty ? Color.secondary.opacity(0.4) : BFColor.primary
                    )
            }
            .disabled((draft.isBlank && pendingAttachments.isEmpty) || model.isPostingComment)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Post comment")
            .accessibilityIdentifier("requests.comment.post")
            .bfPointerHover()
        }
    }
}

private struct CommentRow: View {
    let comment: RQComment
    @ObservedObject var model: ChangeRequestDetailViewModel
    @State private var downloadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.authorName ?? "Someone")
                    .font(RQFont.body.weight(.semibold))
                Spacer()
                if let date = comment.createdAt {
                    Text(date.relativeDescription)
                        .font(RQFont.meta)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            Text(comment.plainTextBody)
                .font(RQFont.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if !comment.attachments.isEmpty {
                ForEach(comment.attachments) { attachment in
                    Button {
                        Task {
                            do {
                                let file = try await model.downloadCommentAttachment(id: attachment.id)
                                await ShareSheetPresenter.present(data: file.data, fileName: file.fileName)
                            } catch {
                                downloadError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label(attachment.fileName, systemImage: "paperclip")
                            .font(RQFont.meta)
                            .foregroundStyle(BFColor.primary)
                    }
                    .buttonStyle(.plain)
                    .bfPointerHover()
                }
            }
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceCard, in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
        .alert("Couldn't open that attachment", isPresented: .constant(downloadError != nil)) {
            Button("OK") { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }
}
