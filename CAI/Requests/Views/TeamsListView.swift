import SwiftUI

// MARK: - Teams Destination
// Ported from trm-ios. Read-only; managing teams stays on the web.

struct TeamsListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            if let model = state.teams {
                TeamsListScreen(model: model, navigationControl: navigationControl)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shellNavigationControl(navigationControl)
            }
        }
    }
}

private struct TeamsListScreen: View {
    @ObservedObject var model: TeamsListViewModel
    let navigationControl: ShellNavigationControl

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search teams")
            content
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
        .shellNavigationControl(navigationControl)
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load(forceRefresh: true) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.teams.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.teams.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "teams")) {
                Task { await model.load(forceRefresh: true) }
            }
        } else if model.filteredTeams.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView("No teams yet", systemImage: "person.2")
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load(forceRefresh: true) } }
                        .listRowSeparator(.hidden)
                }
                ForEach(model.filteredTeams) { team in
                    TeamRow(team: team)
                        .listRowBackground(BFColor.surfaceCanvas)
                        .listRowSeparatorTint(BFColor.hairline)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct TeamRow: View {
    let team: RQTeam

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            VStack(alignment: .leading, spacing: 6) {
                Text(team.name)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                if team.members.isEmpty {
                    Text("No members")
                        .font(RQFont.meta)
                        .foregroundStyle(.tertiary)
                } else {
                    TeamStack(members: team.members)
                }
            }
            Spacer(minLength: 0)
            Text("\(team.members.count)")
                .font(RQFont.meta)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(team.members.count) members")
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .accessibilityIdentifier("requests.teamRow.\(team.id)")
    }
}
