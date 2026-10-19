import SwiftUI

// MARK: - Requests State
// Everything the Requests space keeps alive while the user moves between destinations
// and spaces. Owned by AppShell, like trm-ios's per-section view-model boxes: only one
// destination's view (and its one NavigationStack) is ever mounted (see AppShell.content
// and P6), so the loaded view models live here instead of in the views, and switching
// back reconnects to data that's already on screen rather than refetching it.
//
// The sidebar reads it too: quick filters drive `changeRequests`, and recently viewed
// rows push onto `requestsPath`.

enum ChangeRequestViewMode: String, CaseIterable {
    case list, grid
}

@MainActor
final class RequestsState: ObservableObject {
    @Published private(set) var changeRequests: ChangeRequestListViewModel?
    @Published private(set) var projects: ProjectsListViewModel?
    @Published private(set) var releases: ReleasesListViewModel?
    @Published private(set) var teams: TeamsListViewModel?

    /// The Requests destination's NavigationStack path (change request ids).
    @Published var requestsPath: [String] = []
    @Published var viewMode: ChangeRequestViewMode = .list
    /// Set by ⌘N (or the toolbar) while the Requests space is active.
    @Published var isCreatingRequest = false

    let recents: RecentRequestsStore

    private(set) var services: RequestsServices?
    private(set) var currentUserId: String?

    init(recents: RecentRequestsStore = RecentRequestsStore()) {
        self.recents = recents
    }

    /// Builds the view models for this user. Cheap — nothing loads until a screen asks.
    /// A different user (or no user) drops everything, including recently viewed, so one
    /// account's requests never linger into another's session.
    func configure(services: RequestsServices?, currentUserId: String?) {
        let servicesChanged = (self.services == nil) != (services == nil)
        guard currentUserId != self.currentUserId || servicesChanged else { return }
        let userChanged = self.currentUserId != nil && currentUserId != self.currentUserId
        self.services = services
        self.currentUserId = currentUserId
        requestsPath = []
        if userChanged { recents.removeAll() }

        guard let services, currentUserId != nil else {
            changeRequests = nil
            projects = nil
            releases = nil
            teams = nil
            return
        }
        changeRequests = ChangeRequestListViewModel(
            service: services.changeRequestService,
            currentUserId: currentUserId
        )
        projects = ProjectsListViewModel(service: services.projectService)
        releases = ReleasesListViewModel(service: services.releaseService)
        teams = TeamsListViewModel(service: services.teamService)
    }

    func makeNewRequestModel(lockedProjectId: String? = nil) -> NewChangeRequestViewModel? {
        guard let services else { return nil }
        return NewChangeRequestViewModel(
            changeRequestService: services.changeRequestService,
            projectService: services.projectService,
            referenceDataService: services.referenceDataService,
            currentUserId: currentUserId,
            lockedProjectId: lockedProjectId
        )
    }

    /// Opens a change request on the Requests destination's stack.
    func openRequest(id: String) {
        requestsPath = [id]
    }

    /// ⌘R and pull-to-refresh: reloads whichever list `destination` shows.
    func refresh(_ destination: RequestsDestination) async {
        switch destination {
        case .requests: await changeRequests?.load()
        case .projects: await projects?.load(forceRefresh: true)
        case .releases: await releases?.load()
        case .teams: await teams?.load(forceRefresh: true)
        case .inbox: break
        }
    }
}
