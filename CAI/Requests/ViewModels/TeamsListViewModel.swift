import Foundation

@MainActor
final class TeamsListViewModel: ObservableObject {
    @Published private(set) var teams: [RQTeam] = []
    @Published private(set) var isLoading = false
    @Published var searchText: String = ""
    @Published var error: String?

    private let service: TeamServicing

    init(service: TeamServicing) {
        self.service = service
    }

    var filteredTeams: [RQTeam] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return teams }
        return teams.filter { $0.name.lowercased().contains(query) }
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
            teams = try await service.listTeams(forceRefresh: forceRefresh)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }
}
