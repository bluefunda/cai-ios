import SwiftUI

// MARK: - Git
// The GitHub integration (trm's adminConfig/githubIntegration: connected accounts and their
// repositories, Connect / Disconnect for admins), then trm's web Git screen
// (components/git/gitHome): the abapGit repos, and adding one — shown only when there are
// some, as trm now hides abapGit behind a flag. Diffs, staging and push need the user's
// GitHub credentials, which the web encrypts with a key built into the web app — not ported.

struct GitReposView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            if let services = state.services {
                GitReposScreen(context: context, githubService: services.githubService)
            }
        }
    }
}

private struct GitReposScreen: View {
    let context: AdminContext
    let githubService: GitHubServicing
    @StateObject private var loader = AdminLoader<RQGitRepo>()
    @StateObject private var github = GitHubBox()
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var searchText = ""
    @State private var isCreating = false
    @Environment(\.openURL) private var openURL

    private var filtered: [RQGitRepo] {
        let query = searchText.trimmedValue.lowercased()
        guard !query.isEmpty else { return loader.items }
        return loader.items.filter {
            [$0.title, $0.package, $0.labels, $0.url].contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminScreenHeader(title: "Git")
            ScrollView {
                VStack(alignment: .leading, spacing: BFSpacing._6) {
                    if let model = github.model {
                        GitHubIntegrationSection(model: model)
                    }
                    if !loader.items.isEmpty {
                        abapGitSection
                    }
                }
                .padding(.horizontal, BFSpacing._4)
                .padding(.bottom, BFSpacing._6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adminColumn()
        .navigationTitle("Git")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCreating) {
            NewGitRepoSheet(context: context, onSaved: reload)
        }
        .task {
            if github.model == nil {
                github.model = GitHubIntegrationViewModel(service: githubService, roles: workspace.requestsRoles)
                await github.model?.load()
            }
            if !loader.hasLoaded { await reload() }
        }
        .refreshable {
            await github.model?.refresh()
            await reload()
        }
    }

    /// Hidden while loading, on a failed load and when there are no repos.
    private var abapGitSection: some View {
        VStack(alignment: .leading, spacing: BFSpacing._3) {
            HStack(alignment: .center, spacing: BFSpacing._3) {
                VStack(alignment: .leading, spacing: 2) {
                    GitSectionTitle("abapGit repositories")
                    if let count = adminCount(loader.items.count, "repo", loaded: loader.hasLoaded) {
                        Text(count)
                            .font(RQFont.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: BFSpacing._3)
                Button { isCreating = true } label: {
                    Label("New repo", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .bfPointerHover()
                .accessibilityIdentifier("admin.git.new")
            }
            AdminSearchField(text: $searchText, prompt: "Search repos")
            if let error = loader.error {
                InlineErrorBanner(message: error) { Task { await reload() } }
            }
            VStack(spacing: 0) {
                ForEach(filtered) { repo in
                    GitRepoRow(repo: repo) {
                        if let url = URL(string: repo.url) { openURL(url) }
                    }
                    .padding(.horizontal, BFSpacing._3)
                    if repo.id != filtered.last?.id { BFHairline() }
                }
            }
            .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                    .strokeBorder(BFColor.hairline, lineWidth: 0.5)
            )
        }
    }

    private final class GitHubBox: ObservableObject {
        @Published var model: GitHubIntegrationViewModel?
    }

    private func reload() async {
        await loader.load { try await context.service.gitRepos() }
    }
}

private struct GitRepoRow: View {
    let repo: RQGitRepo
    let openRemote: () -> Void

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.title).font(RQFont.rowTitle).lineLimit(1)
                Text([repo.package, repo.branchShortName, repo.labels].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BFSpacing._2)
            if !repo.url.isEmpty {
                Button(action: openRemote) { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open remote")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NewGitRepoSheet: View {
    let context: AdminContext
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var package = ""
    @State private var branch = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { ![url, package, branch].contains { $0.trimmedValue.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                TextField("Repository URL", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Package", text: $package)
                    .textInputAutocapitalization(.characters)
                TextField("Branch", text: $branch)
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("New Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: canSave, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
        }
    }

    private func save() async {
        isSaving = true
        do {
            try await context.service.createGitRepo(RQNewGitRepo(
                url: url.trimmedValue, package: package.trimmedValue, branchname: branch.trimmedValue
            ))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
