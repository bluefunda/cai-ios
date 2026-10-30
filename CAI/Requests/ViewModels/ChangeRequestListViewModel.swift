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
    var severity: String?     // nil = Any; else "Low"/"Medium"/"High"
    var requestType: String = "" // free text; empty = Any (the wire field has no fixed enum)
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
    @Published var advancedFilters = ChangeRequestAdvancedFilters() {
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

    /// Client-side only — filters the already-fetched (cached) `changeRequests` in memory,
    /// no refetch. Status is set from either the List-mode status chips or the Filter
    /// sheet's Status field; search is instant-as-you-type against the same cached list
    /// rather than a debounced server round-trip, so results appear immediately even for a
    /// single typed character.
    @Published private(set) var statusFilter: ChangeRequestStatus?
    @Published var searchText: String = ""

    func setStatusFilter(_ status: ChangeRequestStatus?) {
        statusFilter = status
    }

    var filteredChangeRequests: [ChangeRequest] {
        var result = changeRequests
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.requestNumber.lowercased().contains(query)
            }
        }
        return result
    }

    private let service: ChangeRequestServicing
    private let currentUserId: String?
    /// Scopes this list to one project's change requests — set only by Project Detail's
    /// embedded list, nil for the top-level Requests screen.
    private let projectId: String?

    init(service: ChangeRequestServicing, currentUserId: String?, projectId: String? = nil) {
        self.service = service
        self.currentUserId = currentUserId
        self.projectId = projectId
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

    /// The board's drag and drop — the same status update the web's Grid view sends on
    /// drop (changeRequestUpdateFunc), then a reload so the card lands in its new column.
    func move(_ id: String, to status: ChangeRequestStatus) async {
        guard let current = changeRequests.first(where: { $0.id == id }), current.status != status else { return }
        do {
            try await service.update(ChangeRequestUpdatePayload(
                id: id,
                createdBy: currentUserId ?? "",
                updatedBy: currentUserId ?? "",
                status: status.rawValue
            ))
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Same params as the web's getChangeRequestByFilter.
    private func filter(offset: Int) -> ChangeRequestFilter {
        ChangeRequestFilter(
            archive: archiveTab == .archived,
            reqOwner: advancedFilters.ownerIsMe ? currentUserId : nil,
            requestType: advancedFilters.requestType.isEmpty ? nil : advancedFilters.requestType,
            severity: advancedFilters.severity,
            assignee: advancedFilters.assigneeIsMe ? currentUserId : nil,
            projectId: projectId,
            limit: Self.pageSize,
            offset: offset
        )
    }
}
