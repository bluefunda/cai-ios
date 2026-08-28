import Foundation

// MARK: - File Attachment Persistence
// Split from the main ChatManager body (and then into its own file) to stay
// under SwiftLint's type_body_length/file_length limits.
extension ChatManager {
    func uploadAttachment(data: Data, filename: String, mimeType: String) async throws -> String? {
        guard let api = apiService else { throw ChatServiceError.notConnected }
        guard let userId = authManager?.currentUser?.id, !userId.isEmpty else {
            throw ChatServiceError.unauthorized
        }
        return try await api.uploadFileForPrompt(data: data, filename: filename, mimeType: mimeType, userId: userId)
    }

    /// The conversation a locally-picked attachment (or voice recording)
    /// should be scoped to — creates a draft conversation if none is active
    /// yet, mirroring sendMessage's own draft-creation fallback.
    func conversationIdForAttachment() -> String {
        if let id = currentConversation?.id { return id }
        newConversation(focus: false)
        return currentConversation!.id
    }

    /// Persists a user-picked file (attachment or voice recording) to
    /// `fileStore` so it survives independent of whether/when it's uploaded.
    @discardableResult
    func saveLocalAttachment(data: Data, filename: String, mimeType: String, conversationId: String) async -> StoredFileMetadata? {
        try? await fileStore.save(
            data: data, filename: filename, mimeType: mimeType,
            conversationId: conversationId, source: .userUpload, remoteURL: nil
        )
    }

    /// Records the backend URL once a previously-saved local attachment finishes uploading.
    func markAttachmentUploaded(_ metadata: StoredFileMetadata, remoteURL: String) {
        Task { try? await fileStore.updateRemoteURL(remoteURL, for: metadata) }
    }

    /// Files (attachments + LLM output) stored locally for a conversation.
    func attachments(for conversationId: String) async -> [StoredFileMetadata] {
        (try? await fileStore.list(conversationId: conversationId)) ?? []
    }

    func deleteAttachment(_ metadata: StoredFileMetadata) async {
        try? await fileStore.delete(metadata)
    }

    /// Scans a finalized assistant response for embedded generated-file links
    /// (matching the web app's markdown-image detection, since the live chat
    /// SSE stream has no structured "output file" field) and downloads/persists
    /// high-confidence matches (markdown images) locally.
    func persistOutputFiles(from content: String, conversationId: String) {
        let links = MessageFileLinks.detect(in: content).filter(\.isImage)
        guard !links.isEmpty else { return }
        Task {
            for link in links {
                await downloadAndPersist(
                    urlString: link.urlString, filename: link.filename,
                    conversationId: conversationId, source: .llmOutput
                )
            }
        }
    }

    /// Persists any structured file references cai-bff now relays on chat
    /// history (`fileUrl`/`fileMetadata`, added by cai-mcp-go) so they're
    /// browsable via LocalFileStore without depending on markdown-embedded
    /// URLs. Skips files already persisted for this conversation.
    func persistHistoryFileReferences(_ messages: [ChatMessage], conversationId: String) {
        Task {
            var seenRemoteURLs = Set((try? await fileStore.list(conversationId: conversationId))?.compactMap(\.remoteURL) ?? [])

            for message in messages {
                if let fileUrl = message.fileUrl, !fileUrl.isEmpty, !seenRemoteURLs.contains(fileUrl) {
                    seenRemoteURLs.insert(fileUrl)
                    let filename = message.fileMetadata?.first?.fileName ?? URL(string: fileUrl)?.lastPathComponent ?? "attachment"
                    await downloadAndPersist(urlString: fileUrl, filename: filename, conversationId: conversationId, source: .userUpload)
                }
                for meta in message.fileMetadata ?? [] {
                    guard let remote = meta.downloadURL ?? meta.originalURL, !remote.isEmpty, !seenRemoteURLs.contains(remote) else { continue }
                    seenRemoteURLs.insert(remote)
                    let filename = meta.fileName ?? URL(string: remote)?.lastPathComponent ?? "file"
                    await downloadAndPersist(urlString: remote, filename: filename, conversationId: conversationId, source: .llmOutput)
                }
            }
        }
    }

    private func downloadAndPersist(urlString: String, filename: String, conversationId: String, source: FileSource) async {
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, response) = try await urlSession.data(from: url)
            let mime = (response as? HTTPURLResponse)?.mimeType ?? "application/octet-stream"
            try await fileStore.save(
                data: data, filename: filename, mimeType: mime,
                conversationId: conversationId, source: source, remoteURL: urlString
            )
        } catch {
            print("[ChatManager] failed to persist file \(urlString): \(error)")
        }
    }
}

// MARK: - Stuck Chat Title Retry
// Split from the main ChatManager body for the same type_body_length/
// file_length reason as the file-attachment extension above.
extension ChatManager {
    /// Matches cai-mcp-go's DefaultChatTitle constant — the placeholder a chat
    /// is created with, before title generation ever runs.
    private static let defaultServerTitle = "New Chat"

    /// Backend title generation is a one-shot, fire-and-forget call made once
    /// when a chat is first created; if that single attempt fails (network
    /// blip, LLM timeout, an expired token at that exact moment), the chat is
    /// left stuck on the server's own default placeholder forever — nothing
    /// else ever retries it. Re-attempts generation in the background for any
    /// loaded chat still on that default, so it self-heals the next time the
    /// chat list loads instead of staying wrong permanently.
    func retryStuckTitles(_ dtos: [ChatSummaryDTO]) {
        guard let api = apiService else { return }
        let stuck = dtos.filter { $0.title == Self.defaultServerTitle && !($0.firstMessage ?? "").isBlank }

        for dto in stuck {
            guard let prompt = dto.firstMessage else { continue }
            Task {
                guard let title = try? await api.generateTitle(chatId: dto.id, message: prompt) else { return }
                if let idx = conversations.firstIndex(where: { $0.id == dto.id }) {
                    conversations[idx].title = title
                }
                if currentConversation?.id == dto.id {
                    currentConversation?.title = title
                }
                cacheUpdateTitle(title, for: dto.id)
            }
        }
    }
}
