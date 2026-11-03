import SwiftUI

// MARK: - Teams Destination
// Ported from trm-ios. Read-only; managing teams stays on the web. A team opens its members
// table (name, email, role), as the web's Teams screen does.

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    NavigationLink(value: team) {
                        TeamRow(team: team)
                    }
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: RQTeam.self) { team in
                TeamMembersView(model: model.membersModel(for: team))
            }
        }
    }
}

private struct TeamMembersView: View {
    @StateObject private var model: TeamMembersViewModel

    init(model: TeamMembersViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search members")
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BFColor.surfaceCanvas)
        .navigationTitle(model.team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.roles.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Role", selection: $model.role) {
                            Text("All roles").tag(String?.none)
                            ForEach(model.roles, id: \.self) { role in
                                Text(role).tag(String?.some(role))
                            }
                        }
                    } label: {
                        Label("Role", systemImage: model.role == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityIdentifier("requests.team.roleFilter")
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.members.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.members.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "this team")) {
                Task { await model.load() }
            }
        } else if model.filteredMembers.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView("No members", systemImage: "person.2")
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            List(model.filteredMembers) { member in
                TeamMemberRow(member: member)
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct TeamMemberRow: View {
    let member: RQAdminUser

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            RQAvatar(urlString: member.profileImage, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !member.role.isEmpty {
                Text(member.role)
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("requests.teamMember.\(member.id)")
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
