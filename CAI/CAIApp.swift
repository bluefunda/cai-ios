import SwiftUI

@main
struct CAIApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var chatManager = ChatManager(service: BFFChatService())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(chatManager)
                .task {
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
                    // Keep BFFAPIService's token in sync whenever AuthManager refreshes
                    if let token = newToken {
                        chatManager.updateToken(token)
                    }
                }
        }
    }
}
