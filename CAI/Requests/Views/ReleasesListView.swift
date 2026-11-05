import SwiftUI

// MARK: - Releases Destination
// Ported from trm-ios: a read-only reimagining of trm web's drag-and-drop release board,
// grouped by planned date. See RequestsModels.swift's RQRelease doc comment for the
// unconfirmed-endpoint caveat this depends on.

struct ReleasesListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            Group {
                if let model = state.releases {
                    ReleasesListScreen(model: model, navigationControl: navigationControl)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shellNavigationControl(navigationControl)
                }
            }
            .navigationDestination(for: String.self) { id in
                ChangeRequestDetailView(changeRequestId: id, state: state)
            }
        }
    }
}

private struct ReleasesListScreen: View {
    @ObservedObject var model: ReleasesListViewModel
    let navigationControl: ShellNavigationControl

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search releases")
            content
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Releases")
        .navigationBarTitleDisplayMode(.inline)
        .shellNavigationControl(navigationControl)
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.sections.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "releases")) {
                Task { await model.load() }
            }
        } else if model.filteredSections.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView("Nothing scheduled yet", systemImage: "shippingbox")
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load() } }
                        .listRowSeparator(.hidden)
                }
                ForEach(model.filteredSections) { section in
                    Section {
                        ForEach(section.releases) { release in
                            RequestRowLink(id: release.changeRequestId) {
                                ReleaseRow(release: release)
                            }
                            .listRowBackground(BFColor.surfaceCanvas)
                            .listRowSeparatorTint(BFColor.hairline)
                        }
                    } header: {
                        Text(sectionTitle(section.date))
                            .font(RQFont.label)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func sectionTitle(_ date: Date?) -> String {
        guard let date else { return "No planned date" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ReleaseRow: View {
    let release: RQRelease

    private var color: Color {
        switch release.status {
        case .planned: return BFColor.statusBlueText
        case .inProgress: return BFColor.statusOrangeText
        case .released: return BFColor.statusGreenText
        case .error: return BFColor.statusRedText
        case .other: return BFColor.statusNeutralText
        }
    }

    private var fill: Color {
        switch release.status {
        case .planned: return BFColor.statusBlueFill
        case .inProgress: return BFColor.statusOrangeFill
        case .released: return BFColor.statusGreenFill
        case .error: return BFColor.statusRedFill
        case .other: return BFColor.statusNeutralFill
        }
    }

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            VStack(alignment: .leading, spacing: 4) {
                if let requestId = release.requestId {
                    Text(requestId)
                        .font(RQFont.number)
                        .foregroundStyle(.secondary)
                }
                Text(release.title)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Label(release.status.displayName, systemImage: release.status.icon)
                .font(RQFont.pill)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(fill, in: Capsule())
                .fixedSize()
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
    }
}
