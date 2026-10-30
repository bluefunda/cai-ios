import SwiftUI

// MARK: - Git
// trm's web Git screen (components/git/gitHome): the abapGit repos, and adding one.
// Diffs, staging and push need the user's GitHub credentials, which the web encrypts
// with a key built into the web app — not ported.

struct GitReposView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            GitReposScreen(context: context)
        }
    }
}

private struct GitReposScreen: View {
    let context: AdminContext
    @StateObject private var loader = AdminLoader<RQGitRepo>()
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
            ListScreenHeader(searchText: $searchText, searchPrompt: "Search repos")
            AdminListContent(loader: loader, subject: "repos", emptyTitle: "No repos",
                             emptyIcon: "arrow.triangle.branch", reload: reload) {
                ForEach(filtered) { repo in
                    GitRepoRow(repo: repo) {
                        if let url = URL(string: repo.url) { openURL(url) }
                    }
                }
            }
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Git")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreating = true } label: { Label("New Repo", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isCreating) {
            NewGitRepoSheet(context: context, onSaved: reload)
        }
        .task { if !loader.hasLoaded { await reload() } }
        .refreshable { await reload() }
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
