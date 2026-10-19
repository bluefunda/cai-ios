import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct CAIApp: App {
    @StateObject private var authManager: AuthManager
    @StateObject private var chatManager = ChatManager(service: BFFChatService())
    @StateObject private var iapManager = IAPManager()
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var unreadPoller: UnreadCountPoller
    /// BlueRequests services share cai's AuthManager for tokens (one identity, P1).
    /// Built eagerly but inert: nothing calls trm-gw unless the Requests space is
    /// available (feature flag + `trm` org) — see `updateRequestsPolling`.
    private let requestsServices: RequestsServices
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = AuthManager()
        _authManager = StateObject(wrappedValue: auth)

        let services = RequestsServices(authManager: auth)
        requestsServices = services
        _unreadPoller = StateObject(wrappedValue: UnreadCountPoller(service: services.notificationsService))
    }

    private let container: ModelContainer = {
        let schema = Schema([PersistedConversation.self, PersistedMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environmentObject(authManager)
                .environmentObject(chatManager)
                .environmentObject(iapManager)
                .environmentObject(workspaceStore)
                .environmentObject(unreadPoller)
                .environment(\.requestsServices, requestsServices)
                // Allow the window to shrink only so far on Mac.
                // Never set an explicit frame here — it fights the window manager
                // and breaks fullscreen.
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        // Raising the floor (not setting an explicit frame) makes the
                        // window open bigger by default without fighting the window
                        // manager / breaking fullscreen, per the note above.
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 1100, height: 750)
                        // The window title bar shows CFBundleDisplayName
                        // ("BlueFunda AI") by default, duplicating the
                        // sidebar's own "BlueFunda AI" header — .navigationTitle
                        // doesn't reach this (it's the title BAR, not a nav
                        // bar), so hide it directly (cai-ios#253).
                        scene.titlebar?.titleVisibility = .hidden
                    }
                    #endif
                }
                .task {
                    chatManager.bind(authManager: authManager)
                    chatManager.bind(iapManager: iapManager)
                    #if DEBUG
                    if ScreenshotFixtures.isEnabled {
                        ScreenshotFixtures.bootstrap(
                            authManager: authManager,
                            chatManager: chatManager,
                            iapManager: iapManager,
                            context: container.mainContext
                        )
                        return
                    }
                    #endif
                    chatManager.configureStorage(container.mainContext)
                    await authManager.restoreSession()
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                    updateRequestsPolling()
                    guard isAuthenticated else { return }
                    #if DEBUG
                    // ScreenshotFixtures.bootstrap already set up everything
                    // this handler exists for — never hit the real network.
                    if ScreenshotFixtures.isEnabled { return }
                    #endif
                    guard let credentials = authManager.getCredentials() else { return }
                    Task {
                        await chatManager.connect(credentials: credentials)
                        // Wire the BFF service into IAPManager so it can register
                        // Apple IAP purchases with the backend.
                        iapManager.bffService = chatManager.apiService
                        await iapManager.syncWithBackend()
                    }
                }
                .onChange(of: authManager.accessToken) { _, newToken in
                    if let token = newToken {
                        chatManager.updateToken(token)
                    }
                }
                // Entitlement follows the token: sign-in, refresh (org membership
                // can change between tokens) and sign-out all land here.
                .onChange(of: authManager.currentUser?.organizations ?? [], initial: true) { _, organizations in
                    workspaceStore.update(organizations: organizations)
                    updateRequestsPolling()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Returning to the foreground can happen after the background
                        // refresh timer was suspended — top up the token so the first
                        // action after resuming never hits an expired session. Also
                        // reconcile any chat stream that was interrupted by
                        // backgrounding (bluefunda/cai-ios#261) — generation continues
                        // server-side regardless, so pull down what was missed.
                        Task {
                            await authManager.refreshOnForeground()
                            await chatManager.reconcileAfterBackground()
                        }
                    case .background:
                        chatManager.noteBackgrounding()
                    default:
                        break
                    }
                    updateRequestsPolling(phase: phase)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: ASAuthorizationAppleIDProvider.credentialRevokedNotification
                )) { _ in
                    Task {
                        await chatManager.disconnect()
                        await authManager.logout()
                    }
                }
        }
        // Replace ⌘N "New Window" with "New Chat" in the File menu
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChatRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    /// Unread polling only runs while BlueRequests is an available space and the app
    /// is in the foreground — personal-only users never hit trm-gw.
    private func updateRequestsPolling(phase: ScenePhase? = nil) {
        unreadPoller.update(
            isRequestsAvailable: authManager.isAuthenticated && workspaceStore.isRequestsAvailable,
            isAppActive: (phase ?? scenePhase) == .active
        )
    }
}
