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

/// The stack a change request's detail was pushed on. Back, and closing it after a
/// delete, return there — a request opened (or created) from a project returns to that
/// project, not the Requests list (web #322).
enum RequestDetailOrigin: Equatable {
    case requests, project, release
}

@MainActor
final class RequestsState: ObservableObject {
    @Published private(set) var changeRequests: ChangeRequestListViewModel?
    @Published private(set) var projects: ProjectsListViewModel?
    @Published private(set) var releases: ReleasesListViewModel?
    @Published private(set) var teams: TeamsListViewModel?
    @Published private(set) var messages: MessagesListViewModel?

    /// The Requests destination's NavigationStack path (change request ids).
    @Published var requestsPath: [String] = []
    /// The Projects destination's path (a project, then its requests), kept here like
    /// `requestsPath` so switching to the Assistant and back returns to the same screen.
    @Published var projectsPath = NavigationPath()
    /// Goes up when a request is saved or deleted, so lists that aren't the Requests
    /// destination's own (a project's requests) reload too.
    @Published var requestsChanged = 0
    @Published var viewMode: ChangeRequestViewMode = .grid
    /// Set by ⌘N (or the toolbar) while the Requests space is active.
    @Published var isCreatingRequest = false
    /// New Request from an assistant answer ("Create change request…"), from any space.
    @Published var newRequestPrefill: NewRequestPrefill?
    /// Why a new request's GitHub issue wasn't created, by change request id: its detail
    /// shows the notice until dismissed.
    @Published var githubIssueNotices: [String: String] = [:]

    let recents: RecentRequestsStore

    private(set) var services: RequestsServices?
    private(set) var currentUserId: String?

    /// `nil` builds the standard store here rather than in a default argument — default
    /// arguments are evaluated outside the main actor, and the store is main-actor bound.
    init(recents: RecentRequestsStore? = nil) {
        self.recents = recents ?? RecentRequestsStore()
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
        projectsPath = NavigationPath()
        githubIssueNotices = [:]
        if userChanged { recents.removeAll() }

        guard let services, currentUserId != nil else {
            changeRequests = nil
            projects = nil
            releases = nil
            teams = nil
            messages = nil
            return
        }
        changeRequests = ChangeRequestListViewModel(
            service: services.changeRequestService,
            workflowService: services.workflowService,
            currentUserId: currentUserId
        )
        projects = ProjectsListViewModel(service: services.projectService)
        releases = ReleasesListViewModel(
            service: services.releaseService, changeRequestService: services.changeRequestService,
            currentUserId: currentUserId)
        teams = TeamsListViewModel(service: services.teamService)
        messages = MessagesListViewModel(service: services.messagesService, currentUserId: currentUserId,
                                         attachmentService: services.attachmentService)
    }

    /// New Request's form, with its draft (per user, and per project when started from one).
    func makeNewRequestModel(lockedProjectId: String? = nil) -> NewChangeRequestViewModel? {
        guard let services else { return nil }
        return NewChangeRequestViewModel(
            changeRequestService: services.changeRequestService,
            projectService: services.projectService,
            referenceDataService: services.referenceDataService,
            sources: NewRequestFormSources(admin: services.adminService),
            currentUserId: currentUserId,
            lockedProjectId: lockedProjectId,
            draftStore: draftStore(projectId: lockedProjectId),
            githubService: services.githubService,
            onGitHubIssueNotice: { [weak self] id, notice in self?.githubIssueNotices[id] = notice }
        )
    }

    func makeNewConversationModel() -> NewConversationViewModel? {
        guard let services else { return nil }
        let adminService = services.adminService
        return NewConversationViewModel(
            messagesService: services.messagesService,
            searchUsers: { _ in try await adminService.allUsers() },
            currentUserId: currentUserId
        )
    }

    /// Where New Request keeps its draft. Injectable so tests use their own defaults.
    var draftDefaults: UserDefaults = .standard

    func draftStore(projectId: String?) -> NewRequestDraftStore? {
        guard let currentUserId else { return nil }
        return NewRequestDraftStore(userId: currentUserId, projectId: projectId, defaults: draftDefaults)
    }

    /// Opens a change request on the Requests destination's stack.
    func openRequest(id: String) {
        requestsPath = [id]
    }

    /// After a request is deleted from its detail: it leaves recently viewed, and the
    /// lists reload. Back on the Requests list, an archived request's list opens on the
    /// Archive tab, where it was (web #320); a project's list just drops it.
    func didDeleteRequest(id: String, wasArchived: Bool, origin: RequestDetailOrigin) async {
        recents.remove(id: id)
        requestsChanged += 1
        if origin == .requests, wasArchived, let changeRequests, changeRequests.archiveTab != .archived {
            // Changing the tab reloads the list.
            changeRequests.archiveTab = .archived
        } else {
            await changeRequests?.load()
        }
    }

    /// ⌘R and pull-to-refresh: reloads whichever list `destination` shows.
    func refresh(_ destination: RequestsDestination) async {
        switch destination {
        case .requests: await changeRequests?.load()
        case .projects: await projects?.load(forceRefresh: true)
        case .releases: await releases?.load()
        case .teams: await teams?.load(forceRefresh: true)
        case .messages: await messages?.load()
        // These screens own their state and reload on pull-to-refresh.
        case .git, .userManagement, .requestTemplates, .manageTeams, .configurations: break
        }
    }
}
