import Foundation

// MARK: - New Request Draft
// A New request form in progress, kept on this device so closing the sheet (or leaving
// for the Assistant) doesn't lose it — the web's newRequestDraft.js (#322). One draft per
// user, and per project when the form was opened from one; it expires after a week.
// Only what the form shows is kept: no files, nothing secret.

struct NewRequestDraft: Codable, Equatable {
    var requestName = ""
    var description = ""
    var requestNumber = ""
    var ticketUrl = ""
    var projectId: String?
    var requestTypeId: String?
    var severityId: String?
    var ownerId: String?
    var templateId: String?
    var teamId: String?
    /// Stage owners by stage order.
    var stageOwners: [Int: String] = [:]
    var platformIds: [String] = []
    var systemId: String?
    var repo = ""
    var qaSource = ""
    var qaTarget = ""
    var prdSource = ""
    var prdTarget = ""
    var createGitHubIssue = false
    var githubIssueRepoId: String?
    /// The assistant answer's chat it started from, linked to the request once created.
    var conversationId: String?

    /// Worth keeping: something the user typed or chose. The project and owner fill in on
    /// their own, so they don't count.
    var hasContent: Bool {
        [requestName, description, requestNumber, ticketUrl, requestTypeId ?? "", severityId ?? "", templateId ?? ""]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Reads and writes one user's (and project's) draft in UserDefaults.
struct NewRequestDraftStore {
    static let keyPrefix = "requests.newRequestDraft"
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    let key: String
    private let defaults: UserDefaults
    private let now: () -> Date

    init(userId: String, projectId: String?, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        key = "\(Self.keyPrefix).\(userId).\(projectId ?? "any")"
        self.defaults = defaults
        self.now = now
    }

    private struct Stored: Codable {
        let draft: NewRequestDraft
        let savedAt: Date
    }

    /// The saved draft, unless it's older than a week (then it's dropped).
    func read() -> NewRequestDraft? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        guard now().timeIntervalSince(stored.savedAt) < Self.lifetime else {
            clear()
            return nil
        }
        return stored.draft
    }

    func save(_ draft: NewRequestDraft) {
        guard let data = try? JSONEncoder().encode(Stored(draft: draft, savedAt: now())) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
