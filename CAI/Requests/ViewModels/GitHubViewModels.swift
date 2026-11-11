import Foundation

// MARK: - GitHub Integration (Git destination)
// trm's GitHub integration settings (adminConfig/githubIntegration), as the cai web's
// GitPage shows it above the abapGit repos: the connected accounts with their repos,
// and Connect / Disconnect for admins. The App's setup URL points at the trm web, which
// finishes the install, so after Connect the user comes back and presses Refresh.

@MainActor
final class GitHubIntegrationViewModel: ObservableObject {
    enum RepoList: Equatable {
        case loading
        case loaded([GitHubRepo])
        case failed(String)
    }

    @Published private(set) var state: GitHubLoadState = .loading
    @Published private(set) var installations: [GitHubInstallation] = []
    /// Each account's repositories; missing until its row asks for them.
    @Published private(set) var repos: [Int64: RepoList] = [:]
    /// Why Connect GitHub is unavailable (the App couldn't be read).
    @Published private(set) var appError: String?
    @Published private(set) var isConnecting = false
    /// Connect opened GitHub: say to finish there, then Refresh.
    @Published private(set) var awaitingInstall = false
    @Published private(set) var isDisconnecting = false
    /// A failed Connect or Disconnect.
    @Published var error: String?

    /// Admins and super-admins connect and disconnect accounts.
    let canManage: Bool
    private let service: GitHubServicing
    private var loadGeneration = 0

    init(service: GitHubServicing, roles: [String]) {
        self.service = service
        self.canManage = GitHubIntegration.canManage(roles: roles)
    }

    /// Only admins can connect, so only they need the App (its install URL). A refresh
    /// keeps the connected accounts on screen until the new list arrives.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if state != .ready { state = .loading }

        var appFailure: Error?
        if canManage {
            do { _ = try await service.app() } catch { appFailure = error }
        }
        do {
            let list = try await service.installations()
            guard generation == loadGeneration else { return }
            installations = list
            repos = [:]
            appError = appFailure.map {
                GitHubIntegration.errorMessage($0, fallback: "Connecting a GitHub account is not available right now.")
            }
            state = .ready
        } catch {
            guard generation == loadGeneration else { return }
            if let appFailure, GitHubIntegration.loadFailureKind(appFailure) == .publicTenant {
                state = .failed(.publicTenant)
            } else {
                state = .failed(GitHubIntegration.loadFailureKind(error))
            }
        }
    }

    func refresh() async {
        awaitingInstall = false
        error = nil
        await load()
    }

    func loadRepos(for installationId: Int64) async {
        repos[installationId] = .loading
        do {
            let list = try await service.installationRepos(installationId: installationId)
            repos[installationId] = .loaded(list)
        } catch {
            repos[installationId] = .failed(
                GitHubIntegration.errorMessage(error, fallback: "Could not load the repositories."))
        }
    }

    /// Fetches a fresh install URL (its signed state expires after 10 minutes) for the
    /// caller to open in the browser; nil, with `error` set, when it can't.
    func connect() async -> URL? {
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        do {
            guard let url = try await service.app().installURL else {
                error = "Could not start the GitHub install. Please try again."
                return nil
            }
            awaitingInstall = true
            return url
        } catch {
            self.error = GitHubIntegration.errorMessage(
                error, fallback: "Could not start the GitHub install. Please try again.")
            return nil
        }
    }

    func disconnect(_ installation: GitHubInstallation) async {
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await service.deleteInstallation(id: installation.installationId)
            installations.removeAll { $0.installationId == installation.installationId }
            repos[installation.installationId] = nil
        } catch {
            self.error = GitHubIntegration.errorMessage(
                error, fallback: "Could not disconnect the installation. Please try again.")
        }
    }
}

// MARK: - Project Repositories
// trm's projectRepos.js: the GitHub repos bound to a project. Admins, super-admins and
// release managers add and remove bindings. Hidden while the API is missing.

@MainActor
final class ProjectReposViewModel: ObservableObject {
    @Published private(set) var state: GitHubLoadState = .loading
    @Published private(set) var bindings: [ProjectRepo] = []
    /// A failed Remove, shown above the list until dismissed.
    @Published var error: String?
    @Published private(set) var isRemoving = false

    // Add a repository
    /// nil until the accounts (and a lone account's repositories) have loaded.
    @Published private(set) var addInstallations: [GitHubInstallation]?
    @Published private(set) var selectedInstallationId: Int64?
    /// nil while the picked account's repositories load.
    @Published private(set) var addRepos: [GitHubRepo]?
    @Published private(set) var addError: String?
    @Published private(set) var isSaving = false

    let projectId: String
    let canBind: Bool
    private let service: GitHubServicing
    /// Ignores a repo list that arrives after another account was picked.
    private var repoRequest = 0

    init(projectId: String, service: GitHubServicing, roles: [String]) {
        self.projectId = projectId
        self.service = service
        self.canBind = GitHubIntegration.canBindProjectRepos(roles: roles)
    }

    func load() async {
        do {
            bindings = try await service.projectRepos(projectId: projectId)
            state = .ready
        } catch {
            state = .failed(GitHubIntegration.loadFailureKind(error))
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// The section is hidden while the endpoint is missing or not set up.
    var isHidden: Bool { state == .failed(.unavailable) }

    var isAddLoading: Bool { addInstallations == nil }
    var isReposLoading: Bool { selectedInstallationId != nil && addRepos == nil && addError == nil }

    /// The picked account's repositories that aren't bound yet.
    var repoOptions: [GitHubRepo] {
        let bound = Set(bindings.map(\.repoNodeId))
        return (addRepos ?? []).filter { !bound.contains($0.nodeId) }
    }

    func repoOptions(matching search: String) -> [GitHubRepo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return repoOptions }
        return repoOptions.filter { $0.fullName.lowercased().contains(query) }
    }

    /// Opening Add: the active accounts, and when there's only one, its repositories too,
    /// so the picker doesn't appear empty and then fill in.
    func prepareAdd() async {
        addInstallations = nil
        selectedInstallationId = nil
        addRepos = nil
        addError = nil
        do {
            let active = try await service.installations().filter(\.isActive)
            if active.count == 1 { await selectInstallation(active[0].installationId) }
            addInstallations = active
        } catch {
            addInstallations = []
            addError = GitHubIntegration.errorMessage(error, fallback: "Could not load the GitHub installations.")
        }
    }

    func selectInstallation(_ installationId: Int64) async {
        selectedInstallationId = installationId
        addRepos = nil
        addError = nil
        repoRequest += 1
        let request = repoRequest
        do {
            let list = try await service.installationRepos(installationId: installationId)
            guard request == repoRequest else { return }
            addRepos = list
        } catch {
            guard request == repoRequest else { return }
            addRepos = []
            addError = GitHubIntegration.errorMessage(
                error, fallback: "Could not load the repositories of this installation.",
                overrides: GitHubIntegration.repoErrorOverrides)
        }
    }

    /// True when the repository was bound (the sheet closes).
    func add(_ repo: GitHubRepo) async -> Bool {
        guard let installationId = selectedInstallationId, !isSaving else { return false }
        isSaving = true
        addError = nil
        defer { isSaving = false }
        do {
            let created = try await service.addProjectRepo(
                projectId: projectId,
                AddProjectRepoPayload(installationId: installationId, repoNodeId: repo.nodeId, fullName: repo.fullName))
            if let created {
                bindings.append(created)
            } else {
                await load()
            }
            return true
        } catch {
            addError = GitHubIntegration.errorMessage(
                error, fallback: "Could not add the repository. Please try again.",
                overrides: GitHubIntegration.repoErrorOverrides)
            return false
        }
    }

    func remove(_ binding: ProjectRepo) async {
        isRemoving = true
        error = nil
        defer { isRemoving = false }
        do {
            try await service.deleteProjectRepo(projectId: projectId, bindingId: binding.id)
            bindings.removeAll { $0.id == binding.id }
        } catch {
            self.error = GitHubIntegration.errorMessage(
                error, fallback: "Could not remove the repository. Please try again.",
                overrides: GitHubIntegration.repoErrorOverrides)
        }
    }
}

// MARK: - GitHub Issues (change request tab)
// trm's changeRequestGitHubIssues: the issues linked to a tech-template request, and
// create / link / unlink. There's no per-request edit permission, so everyone gets the
// actions and the backend answers 403.

@MainActor
final class GitHubIssuesViewModel: ObservableObject {
    @Published private(set) var state: GitHubLoadState = .loading
    @Published private(set) var links: [GitHubIssueLink] = []
    /// nil while loading; empty when the project has no bound repos (or they failed).
    @Published private(set) var repos: [ProjectRepo]?
    @Published private(set) var reposError: String?
    /// A failed Unlink.
    @Published var error: String?
    @Published private(set) var isUnlinking = false
    @Published private(set) var userNames: [String: String] = [:]

    // The create / link dialog
    @Published var dialogMode: GitHubIssueMode?
    @Published var draftRepoId = ""
    @Published var draftTitle = ""
    @Published var draftBody = ""
    @Published var draftNumber = ""
    @Published private(set) var dialogError: String?
    @Published private(set) var isSaving = false
    /// The create/link has run past `slowDelay`: say it can take up to 20 seconds.
    @Published private(set) var isSlow = false

    let changeRequestId: String
    let projectId: String?
    /// The change request's title, the default issue title.
    let defaultTitle: String
    private let service: GitHubServicing
    private let users: () async throws -> [UserOption]
    private let slowDelay: TimeInterval
    private var slowTask: Task<Void, Never>?

    init(changeRequestId: String, projectId: String?, defaultTitle: String, service: GitHubServicing,
         users: @escaping () async throws -> [UserOption] = { [] },
         slowDelay: TimeInterval = GitHubIntegration.slowRequestDelay) {
        self.changeRequestId = changeRequestId
        self.projectId = projectId
        self.defaultTitle = defaultTitle
        self.service = service
        self.users = users
        self.slowDelay = slowDelay
    }

    func load() async {
        state = .loading
        await loadLinks()
        await loadRepos()
        if let list = try? await users() {
            userNames = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func loadLinks() async {
        do {
            links = try await service.issues(changeRequestId: changeRequestId)
            state = .ready
        } catch {
            state = .failed(GitHubIntegration.loadFailureKind(error))
        }
    }

    func retry() async {
        state = .loading
        await loadLinks()
    }

    private func loadRepos() async {
        guard let projectId else {
            repos = []
            return
        }
        do {
            repos = try await service.projectRepos(projectId: projectId)
            reposError = nil
        } catch {
            repos = []
            reposError = GitHubIntegration.errorMessage(error, fallback: "Could not load the project's repositories.")
        }
    }

    var hasRepos: Bool { !(repos ?? []).isEmpty }

    func userName(_ id: String) -> String { userNames[id] ?? id }

    func openDialog(_ mode: GitHubIssueMode) {
        draftRepoId = repos?.count == 1 ? repos![0].id : ""
        draftTitle = defaultTitle
        draftBody = ""
        draftNumber = ""
        dialogError = nil
        dialogMode = mode
    }

    func closeDialog() {
        if !isSaving { dialogMode = nil }
    }

    var draftIssueNumber: Int? { GitHubIntegration.parseIssueNumber(draftNumber) }
    /// Something typed that isn't a positive number.
    var isDraftNumberInvalid: Bool { !draftNumber.isEmpty && draftIssueNumber == nil }

    var canSubmit: Bool {
        guard let dialogMode, !draftRepoId.isEmpty, !isSaving else { return false }
        return dialogMode == .create || draftIssueNumber != nil
    }

    /// Creates or links; the dialog closes on success. A timeout reloads the list, since
    /// the workflow may still have finished.
    func submit() async {
        guard canSubmit, let mode = dialogMode else { return }
        let payload: IssueLinkPayload
        switch mode {
        case .create:
            payload = .create(projectRepoId: draftRepoId, title: draftTitle.trimmedValue, body: draftBody.trimmedValue)
        case .link:
            guard let number = draftIssueNumber else { return }
            payload = .link(projectRepoId: draftRepoId, number: number)
        }
        isSaving = true
        isSlow = false
        dialogError = nil
        let delay = slowDelay
        slowTask?.cancel()
        slowTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isSlow = true
        }
        defer {
            slowTask?.cancel()
            slowTask = nil
            isSaving = false
            isSlow = false
        }
        do {
            let link = try await service.addIssue(changeRequestId: changeRequestId, payload)
            dialogMode = nil
            if let link {
                links = links.filter { $0.id != link.id } + [link]
            } else {
                await loadLinks()
            }
        } catch {
            dialogError = GitHubIntegration.issueErrorMessage(error, mode: mode)
            if GitHubIntegration.isTimeout(error) { await loadLinks() }
        }
    }

    func unlink(_ link: GitHubIssueLink) async {
        isUnlinking = true
        defer { isUnlinking = false }
        do {
            try await service.unlinkIssue(changeRequestId: changeRequestId, linkId: link.id)
            links.removeAll { $0.id == link.id }
        } catch {
            self.error = GitHubIntegration.errorMessage(error, fallback: "Could not unlink the issue. Please try again.")
        }
    }
}
