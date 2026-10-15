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

    @discardableResult
    private func downloadAndPersist(
        urlString: String, filename: String, conversationId: String, source: FileSource
    ) async -> StoredFileMetadata? {
        do {
            return try await downloadToFileStore(
                urlString: urlString, filename: filename, conversationId: conversationId, source: source
            )
        } catch {
            print("[ChatManager] failed to persist file \(urlString): \(error)")
            return nil
        }
    }

    /// Downloads a file into `fileStore`. Throws on a non-2xx response: an expired presigned
    /// link answers 403 with an XML error body, which was previously saved as the file itself.
    private func downloadToFileStore(
        urlString: String, filename: String, conversationId: String, source: FileSource,
        remoteURL: String? = nil
    ) async throws -> StoredFileMetadata {
        guard let url = URL(string: urlString) else { throw GeneratedFileError.unavailable }
        let (data, response) = try await urlSession.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 403 || status == 404 { throw GeneratedFileError.expired }
        guard (200..<300).contains(status) else { throw GeneratedFileError.unavailable }
        let mime = (response as? HTTPURLResponse)?.mimeType ?? "application/octet-stream"
        return try await fileStore.save(
            data: data, filename: filename, mimeType: mime,
            conversationId: conversationId, source: source, remoteURL: remoteURL ?? urlString
        )
    }

    /// A local copy of a file the assistant generated (#371), for Quick Look and sharing:
    /// reuses the copy saved earlier (history load saves these too), else downloads it now.
    func localFileURL(for file: MessageFileMetadata, conversationId: String) async throws -> URL {
        // A saved copy is matched by its storage path (stable) or the link it came from.
        let identities = [file.s3Path, file.downloadURL].compactMap { $0 }.filter { !$0.isEmpty }
        let saved = try? await fileStore.list(conversationId: conversationId)
        if let stored = saved?.first(where: { identities.contains($0.remoteURL ?? "") }) {
            return try previewCopy(of: try await fileStore.fileURL(for: stored), named: stored.filename)
        }
        let link = try await downloadLink(for: file, conversationId: conversationId)
        let filename = file.fileName ?? URL(string: link)?.lastPathComponent ?? "file"
        let stored = try await downloadToFileStore(
            urlString: link, filename: filename, conversationId: conversationId, source: .llmOutput,
            remoteURL: identities.first
        )
        return try previewCopy(of: try await fileStore.fileURL(for: stored), named: stored.filename)
    }

    /// The store names files "<id>_<name>", which Quick Look shows as the title; preview a copy
    /// under the file's real name instead (temporary directory, one folder per stored file).
    private func previewCopy(of url: URL, named filename: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilePreviews", isDirectory: true)
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
        let name = (filename as NSString).lastPathComponent
        let copy = folder.appendingPathComponent(name.isEmpty ? url.lastPathComponent : name)
        if !FileManager.default.fileExists(atPath: copy.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
        }
        return copy
    }

    /// A fresh link from the BFF (the one saved with the reply expires after an hour), falling
    /// back to the saved link if the route isn't reachable.
    private func downloadLink(for file: MessageFileMetadata, conversationId: String) async throws -> String {
        if let s3Path = file.s3Path, !s3Path.isEmpty, let api = apiService {
            do {
                return try await api.fileLink(chatId: conversationId, s3Path: s3Path)
            } catch APIError.serverError(404, _) {
                throw GeneratedFileError.notFound
            } catch {
                print("[ChatManager] fresh file link failed, using the saved link: \(error)")
            }
        }
        guard let link = file.downloadURL, !link.isEmpty else { throw GeneratedFileError.unavailable }
        return link
    }
}

enum GeneratedFileError: LocalizedError {
    case expired
    case notFound
    case unavailable

    var errorDescription: String? {
        switch self {
        case .expired:
            return "This file's download link has expired. Ask again to create it again."
        case .notFound: return "This file is no longer available."
        case .unavailable: return "This file couldn't be downloaded. Please try again."
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
