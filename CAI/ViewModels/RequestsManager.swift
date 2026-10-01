import Foundation

// MARK: - Requests Manager
// State owner for the Requests tab (bluerequests: Change Requests / Projects /
// Releases). Phase 1 is read-only lists; create/edit, detail (stages,
// timeline, comments) and live SSE updates are later phases — see
// RequestsAPIService's doc comment for the endpoints those will need.

@MainActor
final class RequestsManager: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case changeRequests
        case projects
        case releases

        var id: String { rawValue }

        var title: String {
            switch self {
            case .changeRequests: return "Change Requests"
            case .projects: return "Projects"
            case .releases: return "Releases"
            }
        }
    }

    @Published private(set) var changeRequests: [ChangeRequestDTO] = []
    @Published private(set) var projects: [ProjectDTO] = []
    @Published private(set) var releases: [ReleaseDTO] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private var service: RequestsAPIService?

    /// (Re)binds the manager to the current session's auth — call before the
    /// first refresh, and again if the signed-in realm/token source changes.
    func configure(authManager: AuthManager) {
        guard service == nil else { return }
        service = RequestsAPIService.make(authManager: authManager)
    }

    func isEmpty(_ section: Section) -> Bool {
        switch section {
        case .changeRequests: return changeRequests.isEmpty
        case .projects: return projects.isEmpty
        case .releases: return releases.isEmpty
        }
    }

    func refresh(_ section: Section) async {
        guard let service else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            switch section {
            case .changeRequests:
                changeRequests = try await service.fetchChangeRequests()
            case .projects:
                projects = try await service.fetchProjects()
            case .releases:
                releases = try await service.fetchReleases()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
