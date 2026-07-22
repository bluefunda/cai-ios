import Foundation

/// FileManager-backed `FileStore`. Each conversation gets its own directory
/// under Application Support so deleting a conversation's files is a single
/// directory removal; each file is a data blob plus a JSON metadata sidecar.
final class LocalFileStore: FileStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootDirectory = support.appendingPathComponent("Files", isDirectory: true)
        }
    }

    // MARK: - FileStore

    @discardableResult
    func save(
        data: Data,
        filename: String,
        mimeType: String,
        conversationId: String,
        source: FileSource,
        remoteURL: String? = nil
    ) async throws -> StoredFileMetadata {
        let metadata = StoredFileMetadata(
            conversationId: conversationId,
            filename: filename,
            mimeType: mimeType,
            byteSize: data.count,
            source: source,
            remoteURL: remoteURL
        )
        try write(data: data, metadata: metadata)
        return metadata
    }

    func load(_ metadata: StoredFileMetadata) async throws -> Data {
        let url = try dataURL(for: metadata)
        guard fileManager.fileExists(atPath: url.path) else { throw FileStoreError.notFound }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileStoreError.ioError(error.localizedDescription)
        }
    }

    func list(conversationId: String) async throws -> [StoredFileMetadata] {
        let dir = try conversationDirectory(conversationId)
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder.fileStore
        let metadataFiles = contents.filter { $0.lastPathComponent.hasSuffix(".meta.json") }
        let results: [StoredFileMetadata] = metadataFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(StoredFileMetadata.self, from: data)
        }
        return results.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(_ metadata: StoredFileMetadata) async throws {
        try? fileManager.removeItem(at: dataURL(for: metadata))
        try? fileManager.removeItem(at: metadataURL(id: metadata.id, conversationId: metadata.conversationId))
    }

    func deleteAll(conversationId: String) async throws {
        let dir = try conversationDirectory(conversationId)
        try? fileManager.removeItem(at: dir)
    }

    func fileURL(for metadata: StoredFileMetadata) async throws -> URL {
        let url = try dataURL(for: metadata)
        guard fileManager.fileExists(atPath: url.path) else { throw FileStoreError.notFound }
        return url
    }

    @discardableResult
    func updateRemoteURL(_ remoteURL: String, for metadata: StoredFileMetadata) async throws -> StoredFileMetadata {
        let updated = StoredFileMetadata(
            id: metadata.id,
            conversationId: metadata.conversationId,
            filename: metadata.filename,
            mimeType: metadata.mimeType,
            byteSize: metadata.byteSize,
            createdAt: metadata.createdAt,
            source: metadata.source,
            remoteURL: remoteURL
        )
        try writeMetadata(updated)
        return updated
    }

    // MARK: - Paths

    private func conversationDirectory(_ conversationId: String) throws -> URL {
        let dir = rootDirectory.appendingPathComponent(conversationId, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw FileStoreError.ioError(error.localizedDescription)
            }
        }
        return dir
    }

    private func dataURL(for metadata: StoredFileMetadata) throws -> URL {
        try conversationDirectory(metadata.conversationId)
            .appendingPathComponent("\(metadata.id)_\(sanitize(metadata.filename))")
    }

    private func metadataURL(id: String, conversationId: String) throws -> URL {
        try conversationDirectory(conversationId).appendingPathComponent("\(id).meta.json")
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "file" : cleaned
    }

    // MARK: - Writing

    private func write(data: Data, metadata: StoredFileMetadata) throws {
        do {
            try data.write(to: try dataURL(for: metadata), options: .atomic)
        } catch {
            throw FileStoreError.ioError(error.localizedDescription)
        }
        try writeMetadata(metadata)
    }

    private func writeMetadata(_ metadata: StoredFileMetadata) throws {
        do {
            let encoded = try JSONEncoder.fileStore.encode(metadata)
            try encoded.write(to: try metadataURL(id: metadata.id, conversationId: metadata.conversationId), options: .atomic)
        } catch {
            throw FileStoreError.ioError(error.localizedDescription)
        }
    }
}

// MARK: - Codable helpers

private extension JSONEncoder {
    static let fileStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let fileStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
