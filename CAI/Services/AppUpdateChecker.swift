import Foundation

// MARK: - App Update Checker
// Asks cai-bff which app version is current (GET /app-version, public, through
// cai-gw) and compares it with the installed one: older than `latest` offers an
// update, older than `minimum` requires one. Checked on launch and on returning to
// the foreground; a failed check changes nothing.

/// One platform's entry from GET /app-version?platform=….
struct AppVersionInfo: Decodable, Equatable {
    let latest: String
    let minimum: String
    var storeUrl: String?
}

enum AppUpdateState: Equatable {
    case upToDate
    /// A newer version is in the store; the app keeps working.
    case available(latest: String, storeURL: URL?)
    /// The installed version is below the minimum: it must update to be used.
    case required(latest: String, storeURL: URL?)
}

enum AppVersionComparison {
    /// Compares dotted versions numerically ("2.10.0" > "2.9.1"); missing parts count
    /// as 0 and anything non-numeric in a part is ignored.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs), right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published private(set) var state: AppUpdateState = .upToDate
    /// The `latest` whose banner the user closed, and when: "remind me later" — it stays
    /// closed for `remindAfter`, or until a newer version, whichever comes first.
    @Published private(set) var dismissedVersion: String?
    @Published private(set) var dismissedAt: Date?

    private let currentVersion: String
    private let fetch: () async throws -> AppVersionInfo
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastChecked: Date?

    /// Server responses are cached for 5 minutes; checking more often gains nothing.
    static let minimumInterval: TimeInterval = 300
    /// How long a closed banner stays closed (Siren and Play's guidance: ask again after a few days).
    static let remindAfter: TimeInterval = 3 * 24 * 60 * 60
    private static let dismissedKey = "appUpdate.dismissedVersion"
    private static let dismissedAtKey = "appUpdate.dismissedAt"

    init(
        currentVersion: String = AppUpdateChecker.installedVersion,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping () async throws -> AppVersionInfo = AppUpdateChecker.fetchFromServer
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        dismissedVersion = defaults.string(forKey: Self.dismissedKey)
        dismissedAt = defaults.object(forKey: Self.dismissedAtKey) as? Date
    }

    var showsBanner: Bool {
        guard case .available(let latest, _) = state else { return false }
        guard latest == dismissedVersion, let dismissedAt else { return true }
        return now().timeIntervalSince(dismissedAt) >= Self.remindAfter
    }

    var isUpdateRequired: Bool {
        if case .required = state { return true }
        return false
    }

    var storeURL: URL? {
        switch state {
        case .upToDate: return nil
        case .available(_, let url), .required(_, let url): return url
        }
    }

    /// Fetches and applies the current versions, at most once per `minimumInterval`
    /// unless `force`.
    func check(force: Bool = false) async {
        if !force, let lastChecked, now().timeIntervalSince(lastChecked) < Self.minimumInterval { return }
        lastChecked = now()
        guard let info = try? await fetch() else { return }
        state = Self.state(current: currentVersion, info: info)
    }

    func dismissBanner() {
        guard case .available(let latest, _) = state else { return }
        dismissedVersion = latest
        dismissedAt = now()
        defaults.set(latest, forKey: Self.dismissedKey)
        defaults.set(dismissedAt, forKey: Self.dismissedAtKey)
    }

    static func state(current: String, info: AppVersionInfo) -> AppUpdateState {
        let url = info.storeUrl.flatMap(URL.init(string:))
        if AppVersionComparison.compare(current, info.minimum) == .orderedAscending {
            return .required(latest: info.latest, storeURL: url)
        }
        if AppVersionComparison.compare(current, info.latest) == .orderedAscending {
            return .available(latest: info.latest, storeURL: url)
        }
        return .upToDate
    }

    // MARK: Live values

    nonisolated static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The Mac app has its own entry, so its versions can move separately.
    nonisolated static var platform: String {
        #if targetEnvironment(macCatalyst)
        return "macos"
        #else
        return "ios"
        #endif
    }

    nonisolated static func fetchFromServer() async throws -> AppVersionInfo {
        var components = URLComponents(string: AppConfig.bffBaseURL + "/app-version")
        components?.queryItems = [URLQueryItem(name: "platform", value: platform)]
        guard let url = components?.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(AppVersionInfo.self, from: data)
    }
}
