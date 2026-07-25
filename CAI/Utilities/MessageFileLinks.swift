import Foundation

/// A file-looking link found in an assistant's markdown response.
struct DetectedFileLink: Identifiable, Equatable {
    var id: String { urlString }
    let urlString: String
    let filename: String
    let isImage: Bool
}

/// Detects file references embedded in streamed assistant markdown text.
///
/// The backend has no structured "generated file" field on the chat response
/// (see cai-bff's SSE stream) — like the web app, the model embeds a fetchable
/// URL directly in its markdown, and the client has to notice it. Markdown
/// image syntax is treated as high-confidence (almost always a real generated
/// file, e.g. a chart) and is auto-persisted; other bare links are surfaced
/// for the user to save on demand instead of being fetched automatically.
enum MessageFileLinks {
    // ![alt](url)
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\((https?://[^\s\)]+)\)"#
    )
    // bare https://... URLs not already inside a markdown link/image
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: #"(?<!\]\()(?<!\()(https?://[^\s\)]+)"#
    )

    static func detect(in content: String) -> [DetectedFileLink] {
        var seen = Set<String>()
        var results: [DetectedFileLink] = []

        for match in matches(imageRegex, in: content) {
            guard seen.insert(match).inserted else { continue }
            results.append(DetectedFileLink(urlString: match, filename: filename(for: match), isImage: true))
        }

        for match in matches(bareURLRegex, in: content) where looksLikeFile(match) {
            guard seen.insert(match).inserted else { continue }
            results.append(DetectedFileLink(urlString: match, filename: filename(for: match), isImage: false))
        }

        return results
    }

    private static func matches(_ regex: NSRegularExpression, in content: String) -> [String] {
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }
    }

    /// Known file-like extensions worth surfacing as a bare-link download —
    /// avoids treating every citation/reference URL as a file.
    private static let fileExtensions: Set<String> = [
        "pdf", "csv", "json", "zip", "txt", "xlsx", "xls", "docx", "doc",
        "png", "jpg", "jpeg", "gif", "webp", "heic", "svg"
    ]

    private static func looksLikeFile(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        return fileExtensions.contains(ext)
    }

    private static func filename(for urlString: String) -> String {
        guard let url = URL(string: urlString), !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" else {
            return "file_\(abs(urlString.hashValue))"
        }
        return url.lastPathComponent
    }
}
