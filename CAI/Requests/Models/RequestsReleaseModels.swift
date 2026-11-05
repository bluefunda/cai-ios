import Foundation

// MARK: - Releases
//
// Not a standalone entity — a "release" in trm is a change request tagged with a planned
// release date, normally shown as a drag-and-drop Kanban board (releaseHome.js) grouped by
// `plannedOn`. Confirmed fields (from groupReleasesByPlannedOn + the Kanban card renderer):
// plannedOn, changeRequestId, requestId (display code), status, name/description. No live
// sample was available to verify exact field casing/nullability against (unlike
// ChangeRequest) — decoded defensively, same posture as UserProfile: everything but the
// identifying id is optional and simply doesn't render if absent, rather than crashing.
//
// GET /rest/trm/v1/release (query: id, status) — chosen over the alternate BFF-fronted
// `/releases` path for the same reason as /rest/trm/v1/user and /rest/trm/v1/projects:
// consistent with the established "everything roots under our own /requests base, use the
// endpoint's literal un-prefixed path" convention. This is a call, not a confirmed fact —
// flag with trm-gw's owner if releases don't load once a real backend is reachable.

struct RQRelease: Identifiable, Decodable {
    let changeRequestId: String
    let requestId: String?
    let name: String?
    let description: String?
    let status: ReleaseStatus
    let plannedOn: Date?
    /// The request's platforms. Scheduling one that has any also deploys it on the web
    /// (SAP release control, or a Git merge to PRD), which the app doesn't drive yet.
    var platforms: [ChangeRequestPlatform] = []

    var id: String { changeRequestId }

    var needsWebToSchedule: Bool { !platforms.isEmpty }

    /// Falls back to the requestId display code, then a generic label — a release with
    /// neither a name nor a description is plausible (trm's own Kanban card falls back to
    /// the linked change request's own title in that case, which this model doesn't have).
    var title: String {
        name ?? description ?? requestId.map { "Request \($0)" } ?? "Untitled Release"
    }
}

extension RQRelease {
    private enum CodingKeys: String, CodingKey {
        case changeRequestId, requestId, name, description, status, plannedOn, platform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intId = try? container.decode(Int.self, forKey: .changeRequestId) {
            changeRequestId = String(intId)
        } else {
            changeRequestId = (try? container.decode(String.self, forKey: .changeRequestId)) ?? UUID().uuidString
        }
        requestId = ((try? container.decodeIfPresent(String.self, forKey: .requestId)) ?? nil)
            .flatMap { $0.isEmpty ? nil : $0 }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        let rawStatus = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        status = ReleaseStatus(raw: rawStatus ?? "")
        plannedOn = (try? container.decodeIfPresent(Date.self, forKey: .plannedOn)) ?? nil
        platforms = (try? container.decodeIfPresent([ChangeRequestPlatform].self, forKey: .platform)) ?? []
    }

    // Fixtures/tests construct RQRelease via the compiler-synthesized memberwise init (the
    // custom Decodable init above lives in this extension, so it doesn't suppress it).
}

struct ReleaseListResponse: Decodable, EmptyDecodableResponse {
    let releases: [RQRelease]

    static var empty: Self { Self(releases: []) }

    init(releases: [RQRelease]) {
        self.releases = releases
    }

    private enum CodingKeys: String, CodingKey {
        case releases
    }

    /// Same defensive-null handling as ChangeRequestListResponse — a null array reads as
    /// empty, not a parse failure.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = (try? container.decodeIfPresent([Entry].self, forKey: .releases)) ?? nil
        releases = (entries ?? []).flatMap(\.releases)
    }

    /// GET /release answers `[{"releases": [...]}, {"plannedCount", …}]` (the web reads
    /// `releases[0].releases`), wrapped by the gateway as `{"releases": that}`. A flat
    /// release in the outer list is kept too; the counts entry holds no releases.
    private struct Entry: Decodable {
        let releases: [RQRelease]

        private enum Keys: String, CodingKey { case releases, changeRequestId }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.contains(.releases) {
                releases = (try? c.decode([RQRelease].self, forKey: .releases)) ?? []
            } else if c.contains(.changeRequestId) {
                releases = [try RQRelease(from: decoder)]
            } else {
                releases = []
            }
        }
    }
}

// MARK: - Release Settings
// The web's release settings drawer (releases/releasesSetting.js): the regular release
// cycle (GET/PUT /release-cycle, one row) and one-off custom releases (GET/POST
// /custom-release).

enum ReleaseFrequency: String, CaseIterable, Identifiable {
    case weekly, biweekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Bi weekly"
        case .monthly: return "Monthly"
        }
    }
    /// Weekly and bi weekly releases fall on a weekday; monthly ones on a day of the month.
    var usesWeekday: Bool { self != .monthly }
}

enum ReleaseWeekday: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// A release time as the web writes it: the hour and minute as picked on the device,
/// labelled `+00` (`H:M:00+00`). The web reads it back the same way, ignoring the zone, so
/// the app does too and both show the same time.
struct ReleaseTime: Equatable {
    var hour: Int
    var minute: Int

    var wireValue: String { String(format: "%02d:%02d:00+00", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(wire: String?) {
        let parts = (wire ?? "").split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1].prefix(2)),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    func date(on day: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// The release cycle, as GET /release-cycle returns it (`{"releases": [cycle]}` via the
/// gateway).
struct RQReleaseCycle: Decodable, Equatable {
    var frequency: ReleaseFrequency
    var day: ReleaseWeekday
    /// Day of the month, for a monthly cycle.
    var dayOfMonth: Int?
    var time: ReleaseTime?
    var systemRetry: Bool
    var manualRetry: Bool
    var attempts: Int

    static let `default` = RQReleaseCycle(frequency: .weekly, day: .friday, dayOfMonth: nil,
                                          time: ReleaseTime(hour: 18, minute: 0),
                                          systemRetry: false, manualRetry: false, attempts: 1)

    init(frequency: ReleaseFrequency, day: ReleaseWeekday, dayOfMonth: Int?, time: ReleaseTime?,
         systemRetry: Bool, manualRetry: Bool, attempts: Int) {
        self.frequency = frequency
        self.day = day
        self.dayOfMonth = dayOfMonth
        self.time = time
        self.systemRetry = systemRetry
        self.manualRetry = manualRetry
        self.attempts = attempts
    }

    private enum CodingKeys: String, CodingKey { case frequency, day, date, time, systemRetry, manualRetry, attempts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        frequency = string(.frequency).flatMap(ReleaseFrequency.init(rawValue:)) ?? .weekly
        day = string(.day).flatMap(ReleaseWeekday.init(rawValue:)) ?? .friday
        dayOfMonth = string(.date).flatMap(Int.init)
        time = ReleaseTime(wire: string(.time))
        systemRetry = (try? c.decodeIfPresent(Bool.self, forKey: .systemRetry)) ?? nil ?? false
        manualRetry = (try? c.decodeIfPresent(Bool.self, forKey: .manualRetry)) ?? nil ?? false
        attempts = (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? nil ?? 0
    }
}

/// PUT /release-cycle. The retry count goes as `attempts`, the field the backend reads (the
/// web sends `attempt`, which is dropped, so its count is never saved); a weekday for weekly
/// and bi weekly cycles (the web only checks for "byweekly", so its bi weekly cycles lost
/// their day), the day of the month for monthly ones.
struct ReleaseCyclePayload: Encodable, Equatable {
    let frequency: String
    let systemRetry: Bool
    let attempts: Int
    let manualRetry: Bool
    let createdBy: String
    let time: String
    let day: String?
    let date: String?

    init(_ cycle: RQReleaseCycle, createdBy: String) {
        frequency = cycle.frequency.rawValue
        systemRetry = cycle.systemRetry
        attempts = cycle.systemRetry ? max(cycle.attempts, 1) : 0
        manualRetry = cycle.manualRetry
        self.createdBy = createdBy
        time = (cycle.time ?? ReleaseTime(hour: 18, minute: 0)).wireValue
        day = cycle.frequency.usesWeekday ? cycle.day.rawValue : nil
        date = cycle.frequency.usesWeekday ? nil : cycle.dayOfMonth.map(String.init)
    }
}

/// A one-off release date (GET /custom-release lists the active ones).
struct RQCustomRelease: Decodable, Identifiable, Equatable {
    let id: Int
    let date: Date?
    let time: ReleaseTime?

    private enum CodingKeys: String, CodingKey { case id, date, time }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        let raw = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil
        date = raw.flatMap { Date.fromISO8601($0) ?? Self.dayFormatter.date(from: String($0.prefix(10))) }
        time = ReleaseTime(wire: (try? c.decodeIfPresent(String.self, forKey: .time)) ?? nil)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// POST /custom-release, as the web sends it: the day at 18:30 on the device as an ISO
/// string, and the time the same way as the cycle's.
struct CustomReleasePayload: Encodable, Equatable {
    let date: String
    let time: String
    let createdBy: String

    init(day: Date, time: ReleaseTime, createdBy: String, calendar: Calendar = .current) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let evening = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day) ?? day
        date = formatter.string(from: evening)
        self.time = time.wireValue
        self.createdBy = createdBy
    }
}

/// POST /release (schedule) and PUT /release (move to another date), as the web's release
/// board sends them on drop: `plannedOn` is the day's local midnight as an ISO string.
struct ReleaseSchedulePayload: Encodable, Equatable {
    let changeRequestId: Int
    let description: String
    let plannedOn: String
    var createdBy: String?
    var updatedBy: String?

    static func plannedOn(_ day: Date, calendar: Calendar = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: calendar.startOfDay(for: day))
    }
}

/// RQRelease's own status vocabulary — confirmed distinct from ChangeRequestStatus
/// (releaseHome.js's `statusimages` dict): released, error, planned, inprogress.
enum ReleaseStatus: Hashable {
    case planned
    case inProgress
    case released
    case error
    case other(String)

    init(raw: String) {
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "planned": self = .planned
        case "inprogress", "progress": self = .inProgress
        case "released": self = .released
        case "error": self = .error
        default: self = .other(raw)
        }
    }

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .released: return "Released"
        case .error: return "Error"
        case .other(let raw): return raw.isBlank ? "Unknown" : raw.capitalized
        }
    }

    var icon: String {
        switch self {
        case .planned: return "calendar"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .released: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .other: return "questionmark.circle"
        }
    }
}
