import SwiftUI
import AuthenticationServices

// MARK: - GitHub Integration Views
// The trm web's GitHub screens in the app's Requests style: the Git destination's
// "GitHub integration" section, a project's Repositories and a tech request's GitHub tab.
// Wording is trm's (sentence case).

// MARK: - Shared Parts

/// A capsule label (account status, issue state) in the status tokens.
struct GitHubPill: View {
    enum Tone { case green, red, neutral }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(RQFont.pill)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .fixedSize()
    }

    private var fill: Color {
        switch tone {
        case .green: return BFColor.statusGreenFill
        case .red: return BFColor.statusRedFill
        case .neutral: return BFColor.statusNeutralFill
        }
    }

    private var textColor: Color {
        switch tone {
        case .green: return BFColor.statusGreenText
        case .red: return BFColor.statusRedText
        case .neutral: return BFColor.statusNeutralText
        }
    }
}

/// The GitHub mark, tinted like an SF Symbol.
struct GitHubMarkIcon: View {
    var size: CGFloat = 16

    var body: some View {
        Image("GitHubMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small spinner with what's loading, in place of a section's content.
struct GitHubLoadingRow: View {
    let label: String

    var body: some View {
        HStack(spacing: BFSpacing._2) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A message the user reads and then dismisses (a failed action, a new request's issue).
struct DismissableNotice: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BFColor.happyOrange)
            Text(message)
                .font(RQFont.meta)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .font(RQFont.meta.weight(.semibold))
                .buttonStyle(.borderless)
                .bfPointerHover()
                .accessibilityIdentifier("requests.github.dismissNotice")
        }
        .padding(BFSpacing._3)
        .background(BFColor.statusOrangeFill.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
    }
}

/// Why the GitHub content isn't shown (not available, personal account, no access).
struct GitHubNoticeCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RQFont.rowTitle)
            Text(message)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The notice for a failed load, or nil for `.error` (which gets Retry instead).
    static func forFailure(_ failure: GitHubLoadFailure) -> GitHubNoticeCard? {
        switch failure {
        case .publicTenant:
            return GitHubNoticeCard(title: "Not available for personal accounts",
                                    message: GitHubIntegration.errorMessages["not_available_in_public_tenant"]!)
        case .unavailable:
            return GitHubNoticeCard(title: "GitHub integration is not available",
                                    message: GitHubIntegration.unavailableMessage)
        case .forbidden:
            return GitHubNoticeCard(title: "No access", message: GitHubIntegration.errorMessages["forbidden"]!)
        case .error:
            return nil
        }
    }
}

/// A section heading on the Git destination.
struct GitSectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Git destination: GitHub integration

struct GitHubIntegrationSection: View {
    @ObservedObject var model: GitHubIntegrationViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var disconnectTarget: GitHubInstallation?

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._3) {
            GitSectionTitle("GitHub integration")
            content
        }
        .confirmationDialog(
            "Disconnect \(disconnectTarget?.accountLogin ?? "")?",
            isPresented: Binding(get: { disconnectTarget != nil }, set: { if !$0 { disconnectTarget = nil } }),
            titleVisibility: .visible,
            presenting: disconnectTarget
        ) { installation in
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect(installation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("BlueRequests stops using this installation. The app stays installed on GitHub; uninstall it there if you no longer need it.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            GitHubLoadingRow(label: "Loading GitHub integration…")
        case .failed(let failure):
            if let notice = GitHubNoticeCard.forFailure(failure) {
                notice
            } else {
                RequestsErrorCard(message: "Could not load the GitHub integration") {
                    Task { await model.load() }
                }
            }
        case .ready:
            ready
        }
    }

    /// GitHub's install page, through the web's start page, in an auth session: once
    /// connected, the web's callback page returns to cai://oauth/github-app/done, which
    /// completes the session. A closed sheet is a cancellation; the list reloads either way.
    private func install(_ installURL: URL) async {
        guard let startURL = GitHubIntegration.appInstallURL(installURL) else {
            openURL(installURL)
            return
        }
        _ = try? await webAuthenticationSession.authenticate(using: startURL, callbackURLScheme: "cai")
        await model.refresh()
    }

    @ViewBuilder
    private var ready: some View {
        if model.canManage {
            VStack(alignment: .leading, spacing: BFSpacing._2) {
                Text("Install the BlueRequests GitHub App on a GitHub organization or account, then bind its repositories to projects.")
                    .font(RQFont.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        if let url = await model.connect() { await install(url) }
                    }
                } label: {
                    Label { Text("Connect GitHub") } icon: { GitHubMarkIcon() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BFColor.primary)
                .disabled(model.isConnecting || model.appError != nil)
                .bfPointerHover()
                .accessibilityIdentifier("requests.git.connectGitHub")
            }
        } else {
            Text("Only admins can connect or disconnect GitHub accounts.")
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        }
        if let appError = model.appError {
            Text(appError)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        }
        if model.awaitingInstall {
            HStack(spacing: BFSpacing._3) {
                Text("Finish installing the app on GitHub, then press Refresh.")
                    .font(RQFont.meta)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Refresh") { Task { await model.refresh() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .bfPointerHover()
                    .accessibilityIdentifier("requests.git.refreshGitHub")
            }
            .padding(BFSpacing._3)
            .background(BFColor.statusBlueFill, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
        }
        if let error = model.error {
            DismissableNotice(message: error) { model.error = nil }
        }

        RQFieldLabel("Connected accounts")
            .padding(.top, BFSpacing._1)
        if model.installations.isEmpty {
            HStack(spacing: BFSpacing._2) {
                GitHubMarkIcon().foregroundStyle(.secondary)
                Text("No GitHub accounts are connected yet.")
                    .font(RQFont.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, BFSpacing._2)
        } else {
            VStack(spacing: BFSpacing._2) {
                ForEach(model.installations) { installation in
                    InstallationCard(model: model, installation: installation) {
                        disconnectTarget = installation
                    }
                }
            }
        }
    }
}

private struct InstallationCard: View {
    @ObservedObject var model: GitHubIntegrationViewModel
    let installation: GitHubInstallation
    let onDisconnect: () -> Void

    private var needsRepos: Bool { model.repos[installation.installationId] == nil }

    private var meta: String {
        [installation.accountTypeLabel,
         installation.createdAt.map { "Connected \($0.formatted(date: .abbreviated, time: .omitted))" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            HStack(alignment: .center, spacing: BFSpacing._3) {
                GitHubMarkIcon(size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installation.accountLogin)
                        .font(RQFont.rowTitle)
                        .lineLimit(1)
                    Text(meta)
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: BFSpacing._2)
                GitHubPill(text: installation.statusLabel, tone: installation.isActive ? .green : .red)
                if model.canManage {
                    Button("Disconnect", role: .destructive, action: onDisconnect)
                        .buttonStyle(.borderless)
                        .font(RQFont.meta.weight(.semibold))
                        .disabled(model.isDisconnecting)
                        .bfPointerHover()
                        .accessibilityIdentifier("requests.git.disconnect")
                }
            }
            repos
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                .strokeBorder(BFColor.hairline, lineWidth: 0.5)
        )
        .task(id: needsRepos) {
            if needsRepos { await model.loadRepos(for: installation.installationId) }
        }
    }

    @ViewBuilder
    private var repos: some View {
        switch model.repos[installation.installationId] ?? .loading {
        case .loading:
            GitHubLoadingRow(label: "Loading repositories…")
                .padding(.leading, BFSpacing._1)
        case .failed(let message):
            HStack(spacing: BFSpacing._2) {
                Text(message)
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await model.loadRepos(for: installation.installationId) } }
                    .font(RQFont.meta.weight(.semibold))
                    .buttonStyle(.borderless)
                    .bfPointerHover()
            }
        case .loaded(let list) where list.isEmpty:
            Text("No repositories are shared with the app.")
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        case .loaded(let list):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, repo in
                    RepoTreeRow(repo: repo, isLast: index == list.count - 1)
                }
            }
            .padding(.leading, BFSpacing._1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Repositories")
        }
    }
}

/// One repository under its account: a branch off the account's vertical line, then the
/// name, default branch and Private.
private struct RepoTreeRow: View {
    let repo: GitHubRepo
    let isLast: Bool

    var body: some View {
        HStack(spacing: BFSpacing._2) {
            TreeConnector(isLast: isLast)
                .stroke(BFColor.neutral400.opacity(0.6), lineWidth: 1)
                .frame(width: 18)
            Text(repo.fullName)
                .font(RQFont.body)
                .lineLimit(1)
                .truncationMode(.middle)
            if !repo.defaultBranch.isEmpty {
                Label(repo.defaultBranch, systemImage: "arrow.triangle.branch")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if repo.isPrivate {
                Label("Private", systemImage: "lock")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

private struct TreeConnector: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 4
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Project Detail: Repositories

struct ProjectReposSection: View {
    @ObservedObject var model: ProjectReposViewModel
    @State private var showAdd = false
    @State private var removeTarget: ProjectRepo?

    var body: some View {
        if !model.isHidden {
            VStack(alignment: .leading, spacing: BFSpacing._2) {
                HStack {
                    RQFieldLabel("Repositories")
                    Spacer(minLength: BFSpacing._2)
                    if model.canBind && model.state == .ready {
                        Button { showAdd = true } label: {
                            Label("Add repository", systemImage: "plus")
                                .font(RQFont.meta.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .bfPointerHover()
                        .accessibilityIdentifier("projects.repos.add")
                    }
                }
                if let error = model.error {
                    DismissableNotice(message: error) { model.error = nil }
                }
                list
            }
            .confirmationDialog(
                "Remove \(removeTarget?.fullName ?? "")?",
                isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
                titleVisibility: .visible,
                presenting: removeTarget
            ) { binding in
                Button("Remove", role: .destructive) {
                    Task { await model.remove(binding) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The repository is unbound from this project. Nothing changes on GitHub.")
            }
            .sheet(isPresented: $showAdd) {
                AddProjectRepoSheet(model: model)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch model.state {
        case .loading:
            GitHubLoadingRow(label: "Loading repositories…")
        case .failed(.publicTenant):
            Text(GitHubIntegration.errorMessages["not_available_in_public_tenant"]!)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: BFSpacing._2) {
                Text("Could not load the repositories.")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await model.retry() } }
                    .font(RQFont.meta.weight(.semibold))
                    .buttonStyle(.borderless)
                    .bfPointerHover()
            }
        case .ready where model.bindings.isEmpty:
            Text("No repositories are bound yet.")
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
        case .ready:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.bindings) { binding in
                    HStack(spacing: BFSpacing._2) {
                        GitHubMarkIcon(size: 14).foregroundStyle(.secondary)
                        if let url = binding.githubURL {
                            Link(binding.fullName, destination: url)
                                .font(RQFont.body.weight(.semibold))
                                .lineLimit(1)
                                .bfPointerHover()
                        } else {
                            Text(binding.fullName).font(RQFont.body.weight(.semibold))
                        }
                        if !binding.defaultBranch.isEmpty {
                            Label(binding.defaultBranch, systemImage: "arrow.triangle.branch")
                                .font(RQFont.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if model.canBind {
                            Button { removeTarget = binding } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isRemoving)
                            .help("Remove")
                            .bfPointerHover()
                            .accessibilityLabel("Remove \(binding.fullName)")
                            .accessibilityIdentifier("projects.repos.remove")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

/// Add a repository: pick the account (one active account is picked for you), then a
/// repository not bound yet.
private struct AddProjectRepoSheet: View {
    @ObservedObject var model: ProjectReposViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: GitHubRepo?

    var body: some View {
        NavigationStack {
            Group {
                if model.isAddLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Add a repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Add") {
                            guard let selected else { return }
                            Task { if await model.add(selected) { dismiss() } }
                        }
                        .disabled(selected == nil)
                        .accessibilityIdentifier("projects.repos.confirmAdd")
                    }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
        }
        .task { await model.prepareAdd() }
    }

    private var form: some View {
        Form {
            if let error = model.addError {
                Section {
                    Text(error).foregroundStyle(.red).font(RQFont.meta)
                }
            }
            if let installations = model.addInstallations, installations.isEmpty, model.addError == nil {
                Section {
                    Text("No GitHub account is connected. An admin can connect one in GitHub integration settings.")
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
            if let installations = model.addInstallations, !installations.isEmpty {
                Section {
                    Picker("GitHub account", selection: Binding(
                        get: { model.selectedInstallationId },
                        set: { id in
                            selected = nil
                            search = ""
                            if let id { Task { await model.selectInstallation(id) } }
                        }
                    )) {
                        Text("Select…").tag(Int64?.none)
                        ForEach(installations) { installation in
                            Text(installation.accountLogin).tag(Int64?.some(installation.installationId))
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("projects.repos.account")
                }
            }
            if model.isReposLoading {
                Section {
                    GitHubLoadingRow(label: "Loading repositories…")
                }
            } else if model.selectedInstallationId != nil, model.addRepos != nil {
                repositorySection
            }
        }
    }

    private var repositorySection: some View {
        Section("Repository") {
            HStack(spacing: BFSpacing._2) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search repositories", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("projects.repos.search")
            }
            let options = model.repoOptions(matching: search)
            if options.isEmpty {
                Text("No repositories left to add")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
            }
            ForEach(options) { repo in
                Button { selected = repo } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.fullName).foregroundStyle(.primary)
                            if !repo.defaultBranch.isEmpty || repo.isPrivate {
                                Text([repo.defaultBranch, repo.isPrivate ? "Private" : ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(RQFont.meta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selected?.id == repo.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
                .accessibilityAddTraits(selected?.id == repo.id ? .isSelected : [])
            }
        }
    }
}

// MARK: - Change Request Detail: GitHub tab

struct GitHubIssuesTab: View {
    @StateObject private var model: GitHubIssuesViewModel
    @ObservedObject var state: RequestsState
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var pendingUnlink: GitHubIssueLink?

    init(model: @autoclosure @escaping () -> GitHubIssuesViewModel, state: RequestsState) {
        _model = StateObject(wrappedValue: model())
        self.state = state
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                DismissableNotice(message: error) { model.error = nil }
                    .padding(.horizontal, BFSpacing._4)
                    .padding(.top, BFSpacing._2)
            }
            content
        }
        .sheet(item: $model.dialogMode) { mode in
            GitHubIssueSheet(model: model, mode: mode)
        }
        .confirmationDialog(
            "Unlink \(pendingUnlink.map { "\($0.repoFullName)#\($0.number)" } ?? "")?",
            isPresented: Binding(get: { pendingUnlink != nil }, set: { if !$0 { pendingUnlink = nil } }),
            titleVisibility: .visible,
            presenting: pendingUnlink
        ) { link in
            Button("Unlink", role: .destructive) {
                Task { await model.unlink(link) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The issue is removed from this change request only. Nothing changes on GitHub: the issue stays open or closed as it is.")
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(.error):
            RequestsErrorCard(message: "Could not load the linked issues.") {
                Task { await model.retry() }
            }
        case .failed(let failure):
            message(failureMessage(failure))
        case .ready:
            ready
        }
    }

    private func failureMessage(_ failure: GitHubLoadFailure) -> String {
        switch failure {
        case .publicTenant: return GitHubIntegration.errorMessages["not_available_in_public_tenant"]!
        case .unavailable: return GitHubIntegration.unavailableMessage
        default: return GitHubIntegration.errorMessages["forbidden"]!
        }
    }

    private func message(_ text: String) -> some View {
        ContentUnavailableView {
            Label { Text("GitHub") } icon: { GitHubMarkIcon(size: 28) }
        } description: {
            Text(text)
        }
    }

    private var ready: some View {
        VStack(spacing: 0) {
            HStack(spacing: BFSpacing._2) {
                Spacer()
                Button { model.openDialog(.link) } label: {
                    Label("Link existing", systemImage: "link")
                        .font(RQFont.body)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("requests.github.link")
                Button { model.openDialog(.create) } label: {
                    Label("Create issue", systemImage: "plus")
                        .font(RQFont.body)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("requests.github.create")
            }
            .controlSize(.small)
            .tint(BFColor.primary)
            .disabled(!model.hasRepos)
            .bfPointerHover()
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._2)

            if model.repos == nil {
                GitHubLoadingRow(label: "Loading repositories…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BFSpacing._4)
            } else if !model.hasRepos {
                noReposHint
                    .padding(.horizontal, BFSpacing._4)
                    .padding(.bottom, BFSpacing._2)
            }

            if model.links.isEmpty {
                ContentUnavailableView {
                    Label { Text("No linked issues") } icon: { GitHubMarkIcon(size: 28) }
                } description: {
                    Text("No GitHub issues are linked to this change request yet.")
                }
            } else {
                List(model.links) { link in
                    IssueLinkRow(link: link, linkedByName: link.linkedBy.map(model.userName)) {
                        pendingUnlink = link
                    }
                    .swipeActions {
                        Button("Unlink", role: .destructive) { pendingUnlink = link }
                    }
                    .listRowBackground(BFColor.surfaceCanvas)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Linked GitHub issues")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Where to bind a repository, and where an admin connects GitHub.
    private var noReposHint: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            Text(model.reposError ?? "No GitHub repositories are bound to this change request's project.")
                .font(RQFont.body)
            Text("Bind a repository in the project's Repositories section. If no GitHub account is connected yet, an admin can connect one in GitHub integration settings.")
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: BFSpacing._3) {
                if let projectId = model.projectId {
                    NavigationLink {
                        ProjectDetailView(projectId: projectId, state: state)
                    } label: {
                        Text("Project's Repositories")
                    }
                    .accessibilityIdentifier("requests.github.openProject")
                }
                Button("GitHub integration settings") {
                    workspace.navigate(to: .requests(.git))
                }
                .accessibilityIdentifier("requests.github.openGit")
            }
            .font(RQFont.meta.weight(.semibold))
            .buttonStyle(.borderless)
            .bfPointerHover()
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
    }
}

private struct IssueLinkRow: View {
    let link: GitHubIssueLink
    let linkedByName: String?
    let onUnlink: () -> Void

    private var meta: String {
        var text = link.originLabel
        if let linkedByName { text += " by \(linkedByName)" }
        if let date = link.linkedAt { text += " on \(date.formatted(date: .abbreviated, time: .omitted))" }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: BFSpacing._3) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(link.repoFullName)
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let url = link.issueURL {
                        Link("#\(link.number)", destination: url)
                            .font(RQFont.number)
                            .bfPointerHover()
                    } else {
                        Text("#\(link.number)").font(RQFont.number)
                    }
                    GitHubPill(text: link.stateLabel, tone: link.isOpen ? .green : .neutral)
                }
                Text(link.title)
                    .font(RQFont.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onUnlink) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(BFColor.errorDelete)
            }
            .buttonStyle(.borderless)
            .help("Unlink")
            .accessibilityLabel("Unlink \(link.repoFullName)#\(link.number)")
            .bfPointerHover()
            .accessibilityIdentifier("requests.github.unlink")
        }
        .padding(.vertical, 4)
    }
}

/// Create a GitHub issue, or link an existing one.
private struct GitHubIssueSheet: View {
    @ObservedObject var model: GitHubIssuesViewModel
    let mode: GitHubIssueMode

    private var title: String { mode == .create ? "Create a GitHub issue" : "Link an existing GitHub issue" }
    private var actionTitle: String { mode == .create ? "Create" : "Link" }
    private var progressText: String { mode == .create ? "Creating the issue on GitHub…" : "Linking the issue…" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Repository", selection: $model.draftRepoId) {
                        Text("Select…").tag("")
                        ForEach(model.repos ?? []) { repo in
                            Text(repo.fullName).tag(repo.id)
                        }
                    }
                    .accessibilityIdentifier("requests.github.repo")
                }
                if mode == .create {
                    Section {
                        TextField("Title", text: $model.draftTitle)
                            .accessibilityIdentifier("requests.github.title")
                    } header: {
                        Text("Title")
                    } footer: {
                        Text("Leave empty to use the change request title.")
                    }
                    Section {
                        TextField("Body (optional)", text: $model.draftBody, axis: .vertical)
                            .lineLimit(4...10)
                            .formMultilineField()
                            .accessibilityIdentifier("requests.github.body")
                    } header: {
                        Text("Body (optional)")
                    } footer: {
                        Text("A link back to this change request is added at the end.")
                    }
                } else {
                    Section {
                        TextField("42", text: $model.draftNumber)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("requests.github.number")
                    } header: {
                        Text("Issue number")
                    } footer: {
                        if model.isDraftNumberInvalid {
                            Text("Enter a positive issue number, for example 42.").foregroundStyle(.red)
                        } else {
                            Text("The issue gets a comment linking back to this change request.")
                        }
                    }
                }
                if model.isSaving {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: BFSpacing._2) {
                            ProgressView().controlSize(.small)
                            Text(progressText + (model.isSlow
                                ? " GitHub is taking a while; this can take up to 20 seconds. Keep this window open."
                                : ""))
                                .font(RQFont.meta)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let error = model.dialogError {
                    Section {
                        Text(error).foregroundStyle(.red).font(RQFont.meta)
                    }
                }
            }
            .disabled(model.isSaving)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.closeDialog() }
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button(actionTitle) { Task { await model.submit() } }
                            .disabled(!model.canSubmit)
                            .accessibilityIdentifier("requests.github.submit")
                    }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
        }
        .presentationDetents([.medium, .large])
    }
}
