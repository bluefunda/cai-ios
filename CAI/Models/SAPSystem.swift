import Foundation

// MARK: - SAP System
// A registered SAP system the Code tab can connect to. Persisted in the
// Keychain (it holds a password), never in UserDefaults or logs.

struct SAPSystem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String        // friendly label, e.g. "A4H Dev"
    var host: String        // full ADT host, e.g. https://sap.example.com:44300
    var client: String      // SAP client, e.g. "100"
    var username: String
    var password: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        client: String,
        username: String,
        password: String
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.client = client
        self.username = username
        self.password = password
    }

    /// Host shown in the UI without the scheme.
    var displayHost: String {
        host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}
