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

    func membersModel(for team: RQTeam) -> TeamMembersViewModel {
        TeamMembersViewModel(team: team, service: service)
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

/// One team's members table: search goes to the server (the web's `name` param), the role
/// filter narrows what's loaded.
@MainActor
final class TeamMembersViewModel: ObservableObject {
    let team: RQTeam
    @Published private(set) var members: [RQAdminUser] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var role: String?
    @Published var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchTask?.cancel()
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }
    private var searchTask: Task<Void, Never>?
    private let service: TeamServicing

    init(team: RQTeam, service: TeamServicing) {
        self.team = team
        self.service = service
    }

    /// Roles among the loaded members, for the filter menu.
    var roles: [String] {
        Array(Set(members.map(\.role).filter { !$0.isEmpty })).sorted()
    }

    var filteredMembers: [RQAdminUser] {
        guard let role else { return members }
        return members.filter { $0.role == role }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let search = searchText.trimmingCharacters(in: .whitespaces)
            let loaded = try await service.members(teamId: team.id, search: search)
            guard !Task.isCancelled, search == searchText.trimmingCharacters(in: .whitespaces) else { return }
            members = loaded
            if let role, !roles.contains(role) { self.role = nil }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
