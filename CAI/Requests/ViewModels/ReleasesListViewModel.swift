import Foundation

/// One date-grouped section, mirroring trm web's Kanban date columns — read-only here
/// instead of drag-and-drop.
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

    private let service: ReleaseServicing

    init(service: ReleaseServicing) {
        self.service = service
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

    func load() async {
        isLoading = true
        error = nil
        do {
            let releases = try await service.listReleases(limit: 5)
            sections = Self.group(releases)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
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
