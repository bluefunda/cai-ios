import SwiftUI

// MARK: - Requests Destination
// Ported from trm-ios's ChangeRequestListView. The view model lives in RequestsState
// (owned by AppShell), so the list survives switching destinations; the stack's path
// lives there too, so the sidebar's "Recently viewed" can push a request onto it.

struct ChangeRequestListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack(path: $state.requestsPath) {
            Group {
                if let model = state.changeRequests {
                    ChangeRequestListScreen(model: model, state: state, navigationControl: navigationControl)
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

private struct ChangeRequestListScreen: View {
    @ObservedObject var model: ChangeRequestListViewModel
    @ObservedObject var state: RequestsState
    let navigationControl: ShellNavigationControl

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showFilterSheet = false

    private var isFiltered: Bool {
        model.statusFilter != nil || model.advancedFilters != ChangeRequestAdvancedFilters()
    }

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(
                searchText: $model.searchText,
                searchPrompt: "Search requests",
                secondaryRowLeading: { ArchiveTogglePicker(model: model) },
                secondaryRowTrailing: { EmptyView() }
            )
            ChangeRequestListBody(model: model, viewMode: effectiveViewMode, showsProject: true)
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                FilterToolbarButton(isActive: isFiltered) { showFilterSheet = true }
                if sizeClass != .compact {
                    ViewModeToolbarPicker(viewMode: $state.viewMode)
                }
                NewRequestToolbarButton { state.isCreatingRequest = true }
            }
        }
        .shellNavigationControl(navigationControl)
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showFilterSheet) {
            ChangeRequestFilterSheet(model: model)
        }
        .sheet(isPresented: $state.isCreatingRequest) {
            if let newModel = state.makeNewRequestModel() {
                NewChangeRequestView(model: newModel) { created in
                    Task { await model.load() }
                    state.openRequest(id: created.id)
                }
            }
        }
    }

    /// Grid only exists on regular width; compact always shows the list.
    private var effectiveViewMode: ChangeRequestViewMode {
        sizeClass == .compact ? .list : state.viewMode
    }
}

/// A dedicated view (not an inline closure over a captured `model`) so it holds `model`
/// as `@ObservedObject` — a hand-rolled Binding over a box's model had no reliable way to
/// redraw when `archiveTab` changed, which let the segmented control drift out of sync
/// (trm-ios). Reused by Project Detail's embedded list.
struct ArchiveTogglePicker: View {
    @ObservedObject var model: ChangeRequestListViewModel

    var body: some View {
        Picker("Active or archived", selection: $model.archiveTab) {
            ForEach(ChangeRequestArchiveTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("requests.archiveTab")
    }
}

// MARK: - List Body

/// Shared by the Requests destination and Project Detail's embedded list, so both get
/// the same rows, chips, empty and error states, and drill-down.
struct ChangeRequestListBody: View {
    @ObservedObject var model: ChangeRequestListViewModel
    let viewMode: ChangeRequestViewMode
    /// False inside Project Detail, where every row is the same project (P6).
    var showsProject = true

    var body: some View {
        VStack(spacing: 0) {
            // Status chips filter the already-fetched list client-side, and only in List
            // mode — the board's columns already group by status.
            if viewMode == .list {
                StatusChipRow(selected: model.statusFilter) { model.setStatusFilter($0) }
            }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.changeRequests.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.changeRequests.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "requests")) {
                Task { await model.load() }
            }
        } else if model.filteredChangeRequests.isEmpty {
            emptyState
        } else if viewMode == .list {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load() } }
                        .listRowSeparator(.hidden)
                }
                ForEach(model.filteredChangeRequests) { cr in
                    RequestRowLink(id: cr.id) {
                        ChangeRequestRow(changeRequest: cr, showsProject: showsProject)
                    }
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ChangeRequestGridView(requests: model.filteredChangeRequests)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView {
                Label("No requests match these filters", systemImage: "doc.text")
            } actions: {
                Button("Clear filters") { model.apply(.all) }
                    .bfPointerHover()
            }
        }
    }
}

/// Pushes a change request. On Mac the row has no chevron (P6) — the same hidden
/// NavigationLink pattern the Agents list uses.
struct RequestRowLink<Content: View>: View {
    let id: String
    @ViewBuilder let label: () -> Content

    var body: some View {
        #if targetEnvironment(macCatalyst)
        ZStack {
            NavigationLink(value: id) { EmptyView() }
                .opacity(0)
            label()
        }
        .contentShape(Rectangle())
        .bfPointerHover()
        .accessibilityIdentifier("requests.crRow.\(id)")
        #else
        NavigationLink(value: id) { label() }
            .accessibilityIdentifier("requests.crRow.\(id)")
        #endif
    }
}

/// Kept data on screen but the latest refresh failed — say so without hiding the list.
struct InlineErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BFColor.happyOrange)
            Text(message)
                .font(RQFont.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .font(RQFont.meta.weight(.semibold))
                .bfPointerHover()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Status Chips

/// "All" plus one chip per wire status, in trm's Kanban column order; colours from the
/// status tokens (P6). Client-side only — never triggers a refetch.
struct StatusChipRow: View {
    let selected: ChangeRequestStatus?
    let onSelect: (ChangeRequestStatus?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BFSpacing._2) {
                chip(label: "All", isSelected: selected == nil, fill: BFColor.secondaryAdaptive) {
                    onSelect(nil)
                }
                ForEach(ChangeRequestStatus.allCases, id: \.self) { status in
                    let style = status.style
                    chip(label: style.label, isSelected: selected == status, fill: style.fill, text: style.text) {
                        onSelect(selected == status ? nil : status)
                    }
                }
            }
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._2)
        }
    }

    private func chip(
        label: String,
        isSelected: Bool,
        fill: Color,
        text: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(RQFont.meta.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, BFSpacing._3)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? (text ?? BFColor.surfaceCanvas) : Color.secondary)
                .background(isSelected ? fill : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : BFColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .bfPointerHover()
    }
}

// MARK: - Row

/// P6 row anatomy, top to bottom: request number + status pill; the project as a small
/// tinted label (only when the list spans projects and the name is known); the title,
/// two lines max; then the mini stage rail on the left and requester + date on the right.
/// Separate visual groups rather than " · "-joined meta strings.
struct ChangeRequestRow: View {
    let changeRequest: ChangeRequest
    var showsProject = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(changeRequest.requestNumber)
                    .font(RQFont.number)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                StatusPill(status: changeRequest.status)
            }

            if showsProject, let project = changeRequest.projectName, !project.isBlank {
                Text(project)
                    .font(RQFont.label)
                    .foregroundStyle(BFColor.secondaryAdaptive)
                    .lineLimit(1)
            }

            Text(changeRequest.title)
                .font(RQFont.rowTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StageRail(
                    stage: changeRequest.stage,
                    totalStages: changeRequest.totalStages,
                    status: changeRequest.status
                )
                if let severity = changeRequest.severity, !severity.isBlank {
                    PriorityPill(text: severity)
                }
                Spacer(minLength: 8)
                OwnerBadge(
                    name: changeRequest.createdByName,
                    avatarURLString: changeRequest.createdByAvatarURL,
                    showsName: false
                )
                if let date = changeRequest.submittedAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(RQFont.meta)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}
