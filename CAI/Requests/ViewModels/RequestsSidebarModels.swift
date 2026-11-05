import Foundation

// MARK: - Recently Viewed Requests
// The Requests space's sidebar context list keeps the last few change requests the
// user opened (docs/BLUEREQUESTS_INTEGRATION.md P3, layer 3b). Stored locally as JSON
// in UserDefaults — just enough to draw a row and reopen the request.

struct RecentRequest: Codable, Equatable, Identifiable {
    let id: String
    let number: String
    let title: String
}

@MainActor
final class RecentRequestsStore: ObservableObject {
    @Published private(set) var items: [RecentRequest] = []

    static let limit = 8
    static let storageKey = "requests_recently_viewed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([RecentRequest].self, from: data) {
            items = Array(decoded.prefix(Self.limit))
        }
    }

    /// Moves `request` to the top, keeping at most `limit` entries.
    func record(_ request: RecentRequest) {
        var updated = items.filter { $0.id != request.id }
        updated.insert(request, at: 0)
        items = Array(updated.prefix(Self.limit))
        persist()
    }

    func record(_ changeRequest: ChangeRequest) {
        record(RecentRequest(id: changeRequest.id, number: changeRequest.requestNumber, title: changeRequest.title))
    }

    /// Clears everything — called when a different user signs in, so one account's
    /// requests never show up in another's sidebar.
    func removeAll() {
        items = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Quick Filters
// One-tap presets in the Requests sidebar. The API has no reviewer facet, so there's no
// "Needs my review"; the presets are All, Mine, and one per wire status.

enum RequestsQuickFilter: Hashable, Identifiable {
    case all
    case mine
    case status(ChangeRequestStatus)

    static var allCases: [RequestsQuickFilter] {
        [.all, .mine] + ChangeRequestStatus.allCases.map { .status($0) }
    }

    var id: String {
        switch self {
        case .all: return "all"
        case .mine: return "mine"
        case .status(let status): return "status.\(status.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all: return "All requests"
        case .mine: return "Mine"
        case .status(let status): return status.style.label
        }
    }

    /// Server-side facets: Mine scopes owner and assignee to the current user; every other
    /// preset widens to anyone (a status preset shows that status across the team).
    var advancedFilters: ChangeRequestAdvancedFilters {
        var filters = ChangeRequestAdvancedFilters()
        let mine = self == .mine
        filters.ownerIsMe = mine
        filters.assigneeIsMe = mine
        return filters
    }

    /// Client-side status facet.
    var statusFilter: ChangeRequestStatus? {
        if case .status(let status) = self { return status }
        return nil
    }

    /// Which preset (if any) the list's current filters correspond to — drives the
    /// sidebar's selected row.
    static func matching(advanced: ChangeRequestAdvancedFilters, status: ChangeRequestStatus?) -> RequestsQuickFilter? {
        let narrowed = advanced.severity != nil || !advanced.requestType.isEmpty
        guard !narrowed else { return nil }
        if let status {
            return (!advanced.ownerIsMe && !advanced.assigneeIsMe) ? .status(status) : nil
        }
        if advanced.ownerIsMe && advanced.assigneeIsMe { return .mine }
        if !advanced.ownerIsMe && !advanced.assigneeIsMe { return .all }
        return nil
    }
}

extension ChangeRequestListViewModel {
    func apply(_ quickFilter: RequestsQuickFilter) {
        setStatusFilter(quickFilter.statusFilter)
        advancedFilters = quickFilter.advancedFilters
    }

    var activeQuickFilter: RequestsQuickFilter? {
        RequestsQuickFilter.matching(advanced: advancedFilters, status: statusFilter)
    }
}
