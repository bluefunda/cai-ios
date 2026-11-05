import Foundation
import UniformTypeIdentifiers

// MARK: - Attachment Service (comment attachments — Postgres `files` table)
// POST /rest/trm/v1/upload + GET /rest/trm/v1/file/{id} — confirmed against trm's own
// changeRequestComments.js upload/download flow. A *different* backend from the CR-level
// Files tab (see CRFileService) — this one is specifically for comment attachments.

enum AttachmentValidationError: LocalizedError {
    case tooLarge
    case unsupportedExtension(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "Files must be 10 MB or smaller."
        case .unsupportedExtension(let ext):
            return "\".\(ext)\" files aren't supported. Allowed: txt, jpg, png, gif, pdf, doc, docx, xls, xlsx, ppt, pptx, xml."
        }
    }
}

protocol AttachmentServicing {
    func upload(fileURL: URL) async throws -> RQAttachment
    func download(id: String) async throws -> (data: Data, mimeType: String?, fileName: String)
}

struct AttachmentService: AttachmentServicing {
    let client: RequestsAPIClient
    let currentUserProvider: @Sendable () async -> User?

    /// Mirrors trm-backend-go's own validation (fileValidations.go) — enforced client-side
    /// too so a rejection surfaces immediately instead of after a round trip.
    static let maxFileSize = 10 * 1024 * 1024
    static let allowedExtensions: Set<String> = [
        "txt", "jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "xml"
    ]

    static func validate(fileURL: URL, fileSize: Int) throws {
        guard fileSize <= maxFileSize else { throw AttachmentValidationError.tooLarge }
        let ext = fileURL.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw AttachmentValidationError.unsupportedExtension(ext)
        }
    }

    func upload(fileURL: URL) async throws -> RQAttachment {
        guard let user = await currentUserProvider() else { throw RequestsAPIError.notSignedIn }
        let data = try Data(contentsOf: fileURL)
        try Self.validate(fileURL: fileURL, fileSize: data.count)

        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"

        let responseData = try await client.uploadMultipart(
            "/rest/trm/v1/upload",
            data: data,
            filename: fileURL.lastPathComponent,
            mimeType: mimeType,
            fields: ["createdBy": user.id],
            includeAccessTokenHeader: false
        )
        let decoded = try RequestsAPIClient.makeDecoder().decode(FileUploadResponse.self, from: responseData)
        guard let first = decoded.file.first else {
            throw RequestsAPIError.serverError(200, "Upload response had no file entry")
        }
        return RQAttachment(id: first.id, fileName: first.name)
    }

    func download(id: String) async throws -> (data: Data, mimeType: String?, fileName: String) {
        let response: FileDownloadResponse = try await client.get("/rest/trm/v1/file/\(id)")
        guard let first = response.file.first else {
            throw RequestsAPIError.serverError(200, "Download response had no file entry")
        }
        return (first.data, first.mimeType, first.name)
    }
}
