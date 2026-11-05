import Foundation

/// Type/Owner are client-side only — the BFF-proxied `/projects` fetch this view model uses
/// supports no server-side filtering at all (see ProjectService's own doc comment), so every
/// project is always fetched and these two facets just narrow what's already in memory,
/// same posture as the Requests screen's client-side status chips.
struct ProjectFilters: Equatable {
    var projectType: String?
    var owner: String?
}

@MainActor
final class ProjectsListViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectDetail] = []
    @Published private(set) var isLoading = false
    @Published var searchText: String = ""
    @Published var filters = ProjectFilters()
    @Published var error: String?

    private let service: ProjectServicing

    init(service: ProjectServicing) {
        self.service = service
    }

    /// Distinct, sorted values actually present in the loaded projects — populates the
    /// Filter sheet's pickers without a separate reference-data endpoint.
    var availableProjectTypes: [String] {
        Set(projects.compactMap(\.projectTypeLabel)).sorted()
    }

    var availableOwners: [String] {
        Set(projects.compactMap(\.ownerName)).sorted()
    }

    var filteredProjects: [ProjectDetail] {
        var result = projects
        if let projectType = filters.projectType {
            result = result.filter { $0.projectTypeLabel == projectType }
        }
        if let owner = filters.owner {
            result = result.filter { $0.ownerName == owner }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        return result
    }

    /// True once a load has finished (success or failure) — screens call
    /// `loadIfNeeded()` on appear, so switching back to a destination reconnects to
    /// data already on screen instead of refetching it (see RequestsState).
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load(forceRefresh: false)
    }

    func load(forceRefresh: Bool = true) async {
        isLoading = true
        error = nil
        do {
            projects = try await service.listProjectDetails(forceRefresh: forceRefresh)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }
}
