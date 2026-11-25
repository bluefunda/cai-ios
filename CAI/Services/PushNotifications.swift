import SwiftUI
import os
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// MARK: - Push Notifications
// Phone, tablet and Mac push through Firebase Cloud Messaging (FCM delivers to
// Apple devices through APNs with the key uploaded to Firebase). The bell stays
// the full record; a push is only a reminder of one entry in it.
//
// - Permission is asked once the Requests space is available to the signed-in
//   user, not at first launch.
// - The FCM token is registered with the backend for that user (DeviceService)
//   and removed on sign-out.
// - Tapping a push opens its request or conversation, as the bell does.
// - The app icon badge follows the bell's unread count whenever it is read, so
//   it is recalculated each time the app is opened.

/// Where a tapped push leads.
enum PushTarget: Equatable {
    case request(id: String)
    case conversation(id: String)

    /// The target named by a push's data: changeRequestId, else conversationId.
    init?(userInfo: [AnyHashable: Any]) {
        if let id = Self.string(userInfo["changeRequestId"]) {
            self = .request(id: id)
        } else if let id = Self.string(userInfo["conversationId"]) {
            self = .conversation(id: id)
        } else {
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String where !s.isEmpty: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}

private let pushLog = Logger(subsystem: "com.bluefunda.ai", category: "Push")

@MainActor
final class PushCenter: NSObject, ObservableObject {
    static let shared = PushCenter()

    /// A tapped push waiting for the shell to open it.
    @Published var pendingTarget: PushTarget?

    private var deviceService: DeviceServicing?
    private var fcmToken: String?
    /// The token last registered with the backend, so it isn't sent again.
    private var registeredToken: String?
    /// The permission request and APNs registration of this session.
    private var enableTask: Task<Void, Never>?
    /// Reports presence every minute while the app is in front.
    private var presenceTask: Task<Void, Never>?
    /// The scene is active (`setActive`).
    private var sceneActive = false
    /// The app is the frontmost app. Always true on iPhone and iPad; on the Mac
    /// a window can be open (scene active) while another app is in front.
    private var frontmost = true
    private var frontmostObservers: [NSObjectProtocol] = []

    /// How often the app reports presence while in front; for two minutes after
    /// each report the backend pushes only to this platform's devices.
    static let presenceInterval: Duration = .seconds(60)
    /// No keyboard or mouse input for this long on the Mac counts as away, so the
    /// phone gets the push again.
    static let idleAfter: TimeInterval = 10 * 60

    /// Whether Firebase is set up: false in builds without GoogleService-Info.plist
    /// (tests, previews), where every call here does nothing.
    private(set) var isConfigured = false

    func configure() {
        guard !isConfigured, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        observeFrontmost()
        isConfigured = true
    }

    /// Turns push on for the signed-in user: asks permission (once), registers with
    /// APNs, and registers the FCM token with the backend when it is known.
    func enable(deviceService: DeviceServicing) {
        guard isConfigured else { return }
        self.deviceService = deviceService
        // Sign-in, organizations and roles each re-run this; ask once per session.
        guard enableTask == nil else { return }
        enableTask = Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                allowed = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            }
            guard allowed else { return }
            UIApplication.shared.registerForRemoteNotifications()
            await registerTokenIfNeeded()
        }
    }

    /// Turns push off on sign-out: the backend forgets this device for the user
    /// who is leaving, and the badge is cleared. Called before the session ends,
    /// so the removal is still authorized; afterwards (an expired session) it only
    /// forgets the token locally.
    func disable() async {
        guard isConfigured else { return }
        let service = deviceService
        let token = registeredToken
        setActive(false)
        deviceService = nil
        registeredToken = nil
        enableTask = nil
        setBadge(0)
        guard let service, let token else { return }
        try? await service.unregister(token: token)
    }

    /// The app came to the front (true) or left it (false). While in front (on
    /// the Mac: the frontmost app, and not idle) it reports presence every
    /// minute, so pushes go to this device only. Repeated calls with the same
    /// state leave the running loop alone.
    func setActive(_ active: Bool) {
        sceneActive = active
        updatePresence()
    }

    private func updatePresence() {
        let present = sceneActive && frontmost && deviceService != nil
        guard present != (presenceTask != nil) else { return }
        presenceTask?.cancel()
        presenceTask = nil
        guard present, let service = deviceService else { return }
        let platform = Self.platform
        presenceTask = Task {
            while !Task.isCancelled {
                if !Self.isIdle {
                    try? await service.reportPresence(platform: platform)
                }
                try? await Task.sleep(for: Self.presenceInterval)
            }
        }
    }

    /// On the Mac, follows whether the app is frontmost. Catalyst keeps the
    /// scene active while another app is in front, so AppKit's own activation
    /// notifications (posted in-process) are the signal.
    private func observeFrontmost() {
        #if targetEnvironment(macCatalyst)
        let center = NotificationCenter.default
        for (name, isFront) in [("NSApplicationDidBecomeActiveNotification", true),
                                ("NSApplicationDidResignActiveNotification", false)] {
            frontmostObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    self.frontmost = isFront
                    self.updatePresence()
                }
            })
        }
        #endif
    }

    /// No keyboard, mouse or trackpad input on the Mac for `idleAfter`. Never on
    /// iPhone and iPad, which lock and leave the app instead.
    private static var isIdle: Bool {
        #if targetEnvironment(macCatalyst)
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= idleAfter
        #else
        return false
        #endif
    }

    /// Removes notifications read on another device (a silent push from the
    /// backend): those named, or all of them. The badge comes with the push.
    func clearDelivered(ids: Set<String>, all: Bool) async {
        let center = UNUserNotificationCenter.current()
        if all {
            center.removeAllDeliveredNotifications()
            return
        }
        guard !ids.isEmpty else { return }
        let delivered = await center.deliveredNotifications()
        let gone = delivered.map(\.request).filter { request in
            ids.contains(request.identifier)
                || (request.content.userInfo["notificationId"] as? String).map(ids.contains) == true
        }.map(\.identifier)
        center.removeDeliveredNotifications(withIdentifiers: gone)
    }

    func setBadge(_ count: Int) {
        guard isConfigured else { return }
        UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

    fileprivate func didReceive(fcmToken token: String?) {
        fcmToken = token
        #if DEBUG
        if let token { pushLog.info("FCM token: \(token, privacy: .public)") }
        #endif
        Task { await registerTokenIfNeeded() }
    }

    private func registerTokenIfNeeded() async {
        guard let service = deviceService, let token = fcmToken, token != registeredToken else { return }
        do {
            try await service.register(token: token, platform: Self.platform, appVersion: Self.appVersion)
            registeredToken = token
        } catch {
            pushLog.error("registering the device failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var platform: String {
        #if targetEnvironment(macCatalyst)
        return "macos"
        #else
        return "ios"
        #endif
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

extension PushCenter: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in self.didReceive(fcmToken: fcmToken) }
    }
}

extension PushCenter: UNUserNotificationCenterDelegate {
    // The completion-handler forms, not the async ones: the async forms finish off the main
    // thread, and UIKit asserts when the tap's state-restoration snapshot isn't on it.

    /// A push that arrives while the app is open still shows as a banner; the bell
    /// updates on its own poll.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = PushTarget(userInfo: response.notification.request.content.userInfo)
        let finish = UncheckedCompletion(run: completionHandler)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.pendingTarget = target }
            finish.run()
        }
    }
}

/// Carries UIKit's completion handler to the main queue, where it is called.
private struct UncheckedCompletion: @unchecked Sendable {
    let run: () -> Void
}

/// Hands APNs registration to Firebase. Firebase's method swizzling is off
/// (FirebaseAppDelegateProxyEnabled = NO in Info.plist), so this is explicit.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated { PushCenter.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        // Debug builds from Xcode get development APNs tokens; TestFlight and App
        // Store builds get production ones. Saying so explicitly keeps Firebase
        // from guessing from the provisioning profile, which it can't read on
        // the Mac.
        #if DEBUG
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
        #endif
    }

    /// A silent push: notifications read on another device are cleared here.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["action"] as? String == "clear" else {
            completionHandler(.noData)
            return
        }
        let all = userInfo["all"] as? String == "true"
        let ids = Set(((userInfo["notificationIds"] as? String) ?? "").split(separator: ",").map(String.init))
        let finish = UncheckedFetchCompletion(run: completionHandler)
        Task { @MainActor in
            await PushCenter.shared.clearDelivered(ids: ids, all: all)
            finish.run(.newData)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushLog.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

/// Carries UIKit's background-fetch completion handler into a Task.
private struct UncheckedFetchCompletion: @unchecked Sendable {
    let run: (UIBackgroundFetchResult) -> Void
}
