import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct CAIApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var chatManager = ChatManager(service: BFFChatService())

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
                // Set a comfortable desktop default on first launch.
                // On Catalyst the window starts at this size; user can resize freely.
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 600)
                        let screen = scene.screen
                        let defaultW: CGFloat = min(1200, screen.bounds.width * 0.75)
                        let defaultH: CGFloat = min(800,  screen.bounds.height * 0.85)
                        scene.windows.first?.frame = CGRect(
                            x: (screen.bounds.width  - defaultW) / 2,
                            y: (screen.bounds.height - defaultH) / 2,
                            width: defaultW, height: defaultH
                        )
                    }
                    #endif
                }
                .task {
                    chatManager.configureStorage(container.mainContext)
                    await authManager.restoreSession()
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                    guard isAuthenticated else { return }
                    guard let credentials = authManager.getCredentials() else { return }
                    Task {
                        await chatManager.connect(credentials: credentials)
                    }
                }
                .onChange(of: authManager.accessToken) { _, newToken in
                    if let token = newToken {
                        chatManager.updateToken(token)
                    }
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
    }
}
