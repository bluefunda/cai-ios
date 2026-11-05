import Foundation

/// One date-grouped section, mirroring trm web's Kanban date columns. Scheduling and
/// moving a release use a date picker instead of the web's drag and drop.
struct ReleaseSection: Identifiable {
    let date: Date?  // nil groups releases with no planned date at all
    let releases: [RQRelease]

    var id: Date? { date }
}

@MainActor
final class ReleasesListViewModel: ObservableObject {
    @Published private(set) var sections: [ReleaseSection] = []
    @Published private(set) var isLoading = false
    @Published var searchText: String = ""
    @Published var error: String?
    /// Completed requests with no release yet — the web board's "upcoming" drawer
    /// (GET change-request?status=completed; the backend leaves out released ones).
    @Published private(set) var readyToSchedule: [ChangeRequest] = []
    @Published private(set) var isScheduling = false

    private let service: ReleaseServicing
    private let changeRequestService: ChangeRequestServicing?
    private let currentUserId: String?

    init(service: ReleaseServicing, changeRequestService: ChangeRequestServicing? = nil, currentUserId: String? = nil) {
        self.service = service
        self.changeRequestService = changeRequestService
        self.currentUserId = currentUserId
    }

    var filteredReady: [ChangeRequest] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return readyToSchedule }
        return readyToSchedule.filter {
            $0.title.lowercased().contains(query) || $0.requestNumber.lowercased().contains(query)
        }
    }

    /// Puts a completed request on a release date. Returns the error to show, or nil.
    func schedule(_ request: ChangeRequest, on day: Date) async -> String? {
        guard let userId = currentUserId, let id = Int(request.id) else { return "Sign in to schedule releases." }
        return await write {
            try await self.service.schedule(ReleaseSchedulePayload(
                changeRequestId: id, description: request.title,
                plannedOn: ReleaseSchedulePayload.plannedOn(day), createdBy: userId))
        }
    }

    /// Moves a scheduled release to another date. Returns the error to show, or nil.
    func reschedule(_ release: RQRelease, to day: Date) async -> String? {
        guard let userId = currentUserId, let id = Int(release.changeRequestId) else { return "Sign in to schedule releases." }
        return await write {
            try await self.service.reschedule(ReleaseSchedulePayload(
                changeRequestId: id, description: release.description ?? release.title,
                plannedOn: ReleaseSchedulePayload.plannedOn(day), updatedBy: userId))
        }
    }

    // MARK: Release settings

    @Published private(set) var releaseCycle: RQReleaseCycle?
    @Published private(set) var customReleases: [RQCustomRelease] = []

    func loadSettings() async -> String? {
        do {
            releaseCycle = try await service.releaseCycle() ?? .default
            customReleases = (try? await service.customReleases()) ?? []
            return nil
        } catch {
            releaseCycle = .default
            return error.localizedDescription
        }
    }

    func saveReleaseCycle(_ cycle: RQReleaseCycle) async -> String? {
        guard let userId = currentUserId else { return "Sign in to change release settings." }
        if !cycle.frequency.usesWeekday, cycle.dayOfMonth == nil { return "Pick the day of the month." }
        isScheduling = true
        defer { isScheduling = false }
        do {
            try await service.saveReleaseCycle(ReleaseCyclePayload(cycle, createdBy: userId))
            releaseCycle = cycle
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func addCustomRelease(on day: Date, at time: ReleaseTime) async -> String? {
        guard let userId = currentUserId else { return "Sign in to add a release date." }
        isScheduling = true
        defer { isScheduling = false }
        do {
            try await service.addCustomRelease(CustomReleasePayload(day: day, time: time, createdBy: userId))
            customReleases = (try? await service.customReleases()) ?? customReleases
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func write(_ operation: () async throws -> Void) async -> String? {
        isScheduling = true
        defer { isScheduling = false }
        do {
            try await operation()
        } catch {
            return error.localizedDescription
        }
        await load()
        return nil
    }

    var filteredSections: [ReleaseSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            let matches = section.releases.filter {
                $0.title.lowercased().contains(query) || ($0.requestId?.lowercased().contains(query) ?? false)
            }
            return matches.isEmpty ? nil : ReleaseSection(date: section.date, releases: matches)
        }
    }

    /// True once a load has finished (success or failure) — screens call
    /// `loadIfNeeded()` on appear, so switching back to a destination reconnects to
    /// data already on screen instead of refetching it (see RequestsState).
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            // No limit, as the web loads the board: a cap here hid every release past the
            // first few.
            let releases = try await service.listReleases(limit: nil)
            sections = Self.group(releases)
        } catch {
            self.error = error.localizedDescription
        }
        if let changeRequestService {
            let completed = ChangeRequestFilter(archive: nil, status: ChangeRequestStatus.completed.rawValue)
            readyToSchedule = (try? await changeRequestService.listChangeRequests(filter: completed)) ?? readyToSchedule
        }
        isLoading = false
        hasLoaded = true
    }

    private static func group(_ releases: [RQRelease]) -> [ReleaseSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: releases) { release -> Date? in
            release.plannedOn.map { calendar.startOfDay(for: $0) }
        }
        return grouped
            .map { ReleaseSection(date: $0.key, releases: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case (nil, nil): return false
                case (nil, _): return false  // undated last
                case (_, nil): return true
                case (let l?, let r?): return l < r
                }
            }
    }
}
