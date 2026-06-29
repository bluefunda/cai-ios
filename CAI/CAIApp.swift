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
                // Allow the window to shrink only so far on Mac.
                // Never set an explicit frame here — it fights the window manager
                // and breaks fullscreen.
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 760, height: 520)
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
}
