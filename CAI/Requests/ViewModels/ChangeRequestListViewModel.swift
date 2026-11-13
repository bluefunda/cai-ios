import Foundation

/// Active/Archive tabs — maps directly to `ChangeRequestFilter.archive`, a real server-side
/// facet (trm's own "Active" tab default is archive=false; see that field's doc comment).
enum ChangeRequestArchiveTab: String, CaseIterable {
    case active, archived

    var displayName: String { self == .active ? "Active" : "Archive" }
}

/// The Filter sheet's server-side fields — Owner/Assignee/Severity/Type all map directly to
/// existing `ChangeRequestFilter` query params. Applied as a batch (one refetch) rather than
/// one fetch per field, since a sheet visit usually changes more than one at once.
struct ChangeRequestAdvancedFilters: Equatable {
    var ownerIsMe = true      // Request Owner: Me vs Anyone
    var assigneeIsMe = true   // Assignee: Me vs Anyone — both default true to match the
                               // app's original launch behavior (equivalent to the old `.mine`)
    /// A specific other person, when the Me toggle is off (the web's user lists); nil = Anyone.
    var ownerId: String?
    var assigneeId: String?
    /// Severity and request type ids, as the web's filter sends them: trm-backend-go parses
    /// both as UUIDs and answers an empty list for anything else. nil = Any.
    var severity: String?
    var requestTypeId: String?

    /// Everyone's requests: a project's list starts here, as on the web (its Filter
    /// narrows from there), while the Requests destination starts on Me/Me.
    static let anyone = ChangeRequestAdvancedFilters(ownerIsMe: false, assigneeIsMe: false)

    /// Narrowed past the Me/Anyone presets.
    var isCustom: Bool {
        severity != nil || requestTypeId != nil || (!ownerIsMe && ownerId != nil) || (!assigneeIsMe && assigneeId != nil)
    }
}

@MainActor
final class ChangeRequestListViewModel: ObservableObject {
    @Published private(set) var changeRequests: [ChangeRequest] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    /// Server-side facets — changing either re-queries the server (matching trm's own
    /// architecture for these fields).
    @Published var archiveTab: ChangeRequestArchiveTab = .active {
        didSet {
            guard oldValue != archiveTab else { return }
            scheduleLoad()
        }
    }
    @Published var advancedFilters: ChangeRequestAdvancedFilters {
        didSet {
            guard oldValue != advancedFilters else { return }
            scheduleLoad()
        }
    }

    /// Cancels any still-in-flight load before starting a new one, so switching Active/Archive
    /// (or Filter-sheet fields) quickly can't let a slow, now-stale request's result — success
    /// or failure — land after a newer one and clobber what's already correctly on screen.
    private var loadTask: Task<Void, Never>?

    private func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    /// Status (List-mode chips or the Filter sheet) and search are server-side facets too,
    /// as on the web, so they reach every request and not just the loaded page. The loaded
    /// rows are also filtered in memory meanwhile, so results change as soon as you type;
    /// the debounced server query then replaces them.
    @Published private(set) var statusFilter: ChangeRequestStatus?
    @Published var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchTask?.cancel()
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
                self?.scheduleLoad()
            }
        }
    }
    private var searchTask: Task<Void, Never>?
    static let searchDebounce: Duration = .milliseconds(350)

    func setStatusFilter(_ status: ChangeRequestStatus?) {
        guard status != statusFilter else { return }
        statusFilter = status
        scheduleLoad()
    }

    /// How the search box maps onto the backend's facets: digits look up one request by
    /// id; other text searches title and description. A display number like "CR-1030"
    /// isn't searchable server-side, so it stays an in-memory filter on loaded rows.
    static func serverSearch(for text: String) -> (description: String, id: String?) {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return ("", nil) }
        if query.allSatisfy(\.isNumber) { return ("", query) }
        if query.range(of: #"^[A-Za-z]+-\d+$"#, options: .regularExpression) != nil { return ("", nil) }
        return (query, nil)
    }

    var filteredChangeRequests: [ChangeRequest] {
        var result = changeRequests
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            // The same fields the server search covers (title, description, id), plus the
            // display number, so server results aren't filtered back out.
            result = result.filter {
                $0.title.lowercased().contains(query)
                    || $0.requestNumber.lowercased().contains(query)
                    || ($0.description?.lowercased().contains(query) ?? false)
                    || $0.id == query
            }
        }
        return result
    }

    private let service: ChangeRequestServicing
    private let workflowService: ChangeRequestWorkflowServicing?
    private let currentUserId: String?
    /// Scopes this list to one project's change requests — set only by Project Detail's
    /// embedded list, nil for the top-level Requests screen.
    private let projectId: String?

    /// What the Filter sheet's Reset returns to, and what counts as unfiltered: Me/Me
    /// for the Requests destination, anyone for a project's list.
    let defaultAdvancedFilters: ChangeRequestAdvancedFilters

    init(service: ChangeRequestServicing, workflowService: ChangeRequestWorkflowServicing? = nil,
         currentUserId: String?, projectId: String? = nil) {
        self.service = service
        self.workflowService = workflowService
        self.currentUserId = currentUserId
        self.projectId = projectId
        defaultAdvancedFilters = projectId == nil ? ChangeRequestAdvancedFilters() : .anyone
        advancedFilters = defaultAdvancedFilters
    }

    /// The Filter button shows as on: a status, or the people/classification changed.
    var isFiltered: Bool {
        statusFilter != nil || advancedFilters != defaultAdvancedFilters
    }

    /// True once a load has finished (success or failure) — screens call
    /// `loadIfNeeded()` on appear, so switching back to a destination reconnects to
    /// data already on screen instead of refetching it (see RequestsState).
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    /// The web's CHANGE_REQUEST_PAGE_SIZE.
    static let pageSize = 50
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    /// Cards dropped on the board whose save hasn't finished: each shows in its new
    /// column with a spinner until the reload, and goes back if the save fails.
    @Published private(set) var moving: [String: ChangeRequestStatus] = [:]

    func load() async {
        isLoading = true
        error = nil
        do {
            let result = try await service.listChangeRequests(filter: filter(offset: 0))
            guard !Task.isCancelled else { return }
            changeRequests = result
            hasMore = result.count >= Self.pageSize
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        guard !Task.isCancelled else { return }
        isLoading = false
        hasLoaded = true
    }

    /// The next page, as the web's List view loads on scroll. Rows already shown are
    /// skipped, in case the list shifted between pages.
    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await service.listChangeRequests(filter: filter(offset: changeRequests.count))
            let known = Set(changeRequests.map(\.id))
            changeRequests += page.filter { !known.contains($0.id) }
            hasMore = page.count >= Self.pageSize
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }

    /// The board's drag and drop, as the web's Grid view does it on drop
    /// (changeRequestUpdateFunc → updatestatus): the status update, then the matching stage
    /// move (see `boardStageTarget`), then a reload so the card lands in its new column.
    /// With workflow enforcement on, the backend refuses the stage move; the web ignores
    /// that, and so does this.
    func move(_ id: String, to status: ChangeRequestStatus) async {
        guard moving[id] == nil,
              let current = changeRequests.first(where: { $0.id == id }), current.status != status else { return }
        moving[id] = status
        defer { moving[id] = nil }
        do {
            try await service.update(ChangeRequestUpdatePayload(
                id: id,
                createdBy: currentUserId ?? "",
                updatedBy: currentUserId ?? "",
                status: status.rawValue
            ))
            if let workflowService, let userId = currentUserId, let numericId = Int(id),
               let stage = current.boardStageTarget(for: status) {
                do {
                    try await workflowService.moveStage(StageUpdatePayload(
                        stage: stage, changeRequestId: numericId, updatedBy: userId))
                } catch RequestsAPIError.rejected(_, "workflow_enforced", _) {}
            }
            await load()
        } catch {
            // Reload first: load() clears the error.
            await load()
            self.error = error.localizedDescription
        }
    }

    /// Same params as the web's getChangeRequestByFilter.
    func filter(offset: Int) -> ChangeRequestFilter {
        let search = Self.serverSearch(for: searchText)
        return ChangeRequestFilter(
            description: search.description,
            id: search.id,
            archive: archiveTab == .archived,
            status: statusFilter?.rawValue,
            reqOwner: advancedFilters.ownerIsMe ? currentUserId : advancedFilters.ownerId,
            requestType: advancedFilters.requestTypeId,
            severity: advancedFilters.severity,
            assignee: advancedFilters.assigneeIsMe ? currentUserId : advancedFilters.assigneeId,
            projectId: projectId,
            limit: Self.pageSize,
            offset: offset
        )
    }
}
