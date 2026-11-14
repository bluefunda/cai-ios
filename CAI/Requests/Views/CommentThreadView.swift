import SwiftUI
import UniformTypeIdentifiers

/// Ported from trm-ios: the comment list with a composer pinned underneath, comment
/// attachments upload before posting. Restyled as the web's (#322): each comment is the
/// author's avatar and a bubble sized to its text; the composer is one rounded box —
/// attach, an input that grows with its text, send — at the bottom of the tab.
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

            VStack(alignment: .leading, spacing: BFSpacing._2) {
                if !mentionSuggestions.isEmpty {
                    mentionStrip
                }
                if !pendingAttachments.isEmpty {
                    pendingAttachmentChips
                }
                composer
            }
            .padding(.horizontal, BFSpacing._3)
            .padding(.top, BFSpacing._2)
            .padding(.bottom, BFSpacing._3)
            .background(BFColor.surfaceCanvas)
        }
        .alert("Couldn't attach that file", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
    }

    /// People matching the "@…" being typed at the end of the comment.
    private var mentionSuggestions: [ProjectTeamMember] {
        guard let query = CommentComposition.activeQuery(in: draft) else { return [] }
        let matches = query.isEmpty ? model.mentionCandidates
            : model.mentionCandidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return Array(matches.prefix(8))
    }

    private var mentionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BFSpacing._2) {
                ForEach(mentionSuggestions) { person in
                    Button {
                        draft = CommentComposition.complete(draft, with: person)
                    } label: {
                        Label(person.name, systemImage: "at")
                            .font(RQFont.meta)
                            .padding(.horizontal, BFSpacing._2)
                            .padding(.vertical, 4)
                            .background(BFColor.surfaceSunken, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("requests.comment.mention")
                    .bfPointerHover()
                }
            }
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
        HStack(alignment: .bottom, spacing: 4) {
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

            // Grows with its text, up to a few lines, then scrolls.
            TextField("Add a comment, @ to mention", text: $draft, axis: .vertical)
                .font(RQFont.body)
                .lineLimit(1...6)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
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
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled((draft.isBlank && pendingAttachments.isEmpty) || model.isPostingComment)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Post comment")
            .accessibilityIdentifier("requests.comment.post")
            .bfPointerHover()
        }
        .padding(4)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isComposerFocused ? BFColor.primary.opacity(0.5) : BFColor.hairline, lineWidth: 1)
        )
    }
}

private struct CommentRow: View {
    let comment: RQComment
    @ObservedObject var model: ChangeRequestDetailViewModel
    @State private var downloadError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RQAvatar(urlString: comment.authorImageURL, size: 28)
            // Only as wide as its text, up to a readable width.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(comment.authorName ?? "Someone")
                        .font(RQFont.meta.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let date = comment.createdAt {
                        Text(date.relativeDescription)
                            .font(RQFont.meta)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Text(comment.plainTextBody)
                    .font(RQFont.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

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
                    .padding(.top, 2)
                    .bfPointerHover()
                }
            }
            .padding(.horizontal, BFSpacing._3)
            .padding(.vertical, BFSpacing._2)
            .background(BFColor.surfaceSunken, in: UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 14,
                style: .continuous))
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Couldn't open that attachment", isPresented: .constant(downloadError != nil)) {
            Button("OK") { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }
}
