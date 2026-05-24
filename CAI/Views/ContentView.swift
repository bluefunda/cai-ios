import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        Group {
            if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .alert("Error", isPresented: .constant(authManager.error != nil)) {
            Button("OK") {
                authManager.error = nil
            }
        } message: {
            Text(authManager.error?.localizedDescription ?? "")
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedRealm = "individual"

    let realms = ["individual", "trm"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Logo
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)

                    Text("CAI")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Cognitive AI Interface")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Realm Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Realm")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Realm", selection: $selectedRealm) {
                        ForEach(realms, id: \.self) { realm in
                            Text(realm.uppercased()).tag(realm)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 40)

                // Login Button
                Button {
                    authManager.login(realm: selectedRealm)
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key")
                        Text("Sign in with Keycloak")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                Spacer()

                // Footer
                Text("Powered by BlueFunda")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            ConversationsView(selectedTab: $selectedTab)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            StorageView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: BFFChatService()))
}
