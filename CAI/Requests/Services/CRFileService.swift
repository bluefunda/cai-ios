import Foundation
import UniformTypeIdentifiers

// MARK: - CR File Service (CR-level "Files" tab — minio-backed)
// GET /rest/trm/v1/listchangeRequestFile + POST /rest/trm/v1/changeRequestAddFile —
// confirmed against trm's own viewfiles.js + minio.js. A *different* backend from comment
// attachments (see AttachmentService) — same UI concept, distinct wire.

protocol CRFileServicing {
    func list(projectId: String, changeRequestId: String) async throws -> [CRFile]
    func upload(projectId: String, changeRequestId: String, fileURL: URL) async throws -> CRFile
}

struct CRFileService: CRFileServicing {
    let client: RequestsAPIClient

    private static func path(projectId: String, changeRequestId: String) -> String {
        "\(projectId)/\(changeRequestId)/"
    }

    func list(projectId: String, changeRequestId: String) async throws -> [CRFile] {
        let response: CRFileListResponse = try await client.get(
            "/rest/trm/v1/listchangeRequestFile",
            queryItems: [URLQueryItem(name: "path", value: Self.path(projectId: projectId, changeRequestId: changeRequestId))]
        )
        return response.files
    }

    func upload(projectId: String, changeRequestId: String, fileURL: URL) async throws -> CRFile {
        let data = try Data(contentsOf: fileURL)
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"

        let responseData = try await client.uploadMultipart(
            "/rest/trm/v1/changeRequestAddFile",
            data: data,
            filename: fileURL.lastPathComponent,
            mimeType: mimeType,
            fields: ["id": changeRequestId, "projectid": projectId],
            includeAccessTokenHeader: false
        )
        let decoded = try RequestsAPIClient.makeDecoder().decode(CRFileUploadResponse.self, from: responseData)
        guard let first = decoded.file.first else {
            throw RequestsAPIError.serverError(200, "Upload response had no file entry")
        }
        return first
    }
}
