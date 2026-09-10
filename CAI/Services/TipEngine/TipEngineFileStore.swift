import Foundation

/// Generic Codable-blob-in-Application-Support persistence, shared by every
/// TipEngine component that needs a small piece of state to survive
/// relaunches (interest profile, anti-annoyance state, reward log).
///
/// Mirrors `LocalFileStore`'s URL-resolution and atomic-write pattern
/// (`CAI/Services/Storage/LocalFileStore.swift`) but stores one JSON value
/// per file instead of per-conversation blobs, since none of TipEngine's
/// state is conversation-scoped.
final class TipEngineFileStore<Value: Codable> {
    private let fileURL: URL
    private let fileManager: FileManager

    /// - Parameters:
    ///   - filename: e.g. "interest_profile.json". Stored under
    ///     `Application Support/TipEngine/`.
    ///   - directory: injectable for tests, so they don't touch the real
    ///     Application Support directory.
    init(filename: String, directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root: URL
        if let directory {
            root = directory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            root = support.appendingPathComponent("TipEngine", isDirectory: true)
        }
        self.fileURL = root.appendingPathComponent(filename)
    }

    func load() -> Value? where Value: Decodable {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.tipEngine.decode(Value.self, from: data)
    }

    @discardableResult
    func save(_ value: Value) -> Bool where Value: Encodable {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            guard (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
                return false
            }
        }
        guard let data = try? JSONEncoder.tipEngine.encode(value) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }
}

private extension JSONEncoder {
    static let tipEngine: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let tipEngine: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
