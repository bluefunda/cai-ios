import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        Group {
            if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                AppShell()
            } else {
                LoginView()
            }
        }
        .alert("Error", isPresented: .constant(authManager.error != nil)) {
            Button("OK") { authManager.error = nil }
        } message: {
            Text(authManager.error?.localizedDescription ?? "")
        }
    }
}

// MARK: - App Shell (replaces MainTabView)

struct AppShell: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager

    @State private var sidebarOpen = false
    @State private var activeSheet: AppSheet?
    @State private var safariURL: URL?

    enum AppSheet: String, Identifiable {
        case storage, settings
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // ── Main content ──────────────────────────────
            VStack(spacing: 0) {
                AppTopBar(
                    sidebarOpen: $sidebarOpen,
                    onNewChat: { chatManager.newConversation() }
                )

                ChatView()
            }
            .zIndex(0)

            // ── Dim overlay ───────────────────────────────
            if sidebarOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.25)) { sidebarOpen = false }
                    }
                    .zIndex(1)
                    .transition(.opacity)
            }

            // ── Sidebar drawer ────────────────────────────
            SidebarDrawer(
                isOpen: $sidebarOpen,
                onOpenStorage: { activeSheet = .storage },
                onOpenSettings: { activeSheet = .settings },
                onOpenURL: { safariURL = $0 }
            )
            .frame(width: 300)
            .offset(x: sidebarOpen ? 0 : -310)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: sidebarOpen)
            .zIndex(2)
        }
        .animation(.default, value: sidebarOpen)
        // Dismiss the keyboard whenever the chat-history sidebar opens
        .onChange(of: sidebarOpen) { _, open in
            if open {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .storage: StorageView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Top Bar

struct AppTopBar: View {
    @EnvironmentObject var chatManager: ChatManager
    @Binding var sidebarOpen: Bool
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Two-bar hamburger
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    sidebarOpen.toggle()
                }
            } label: {
                VStack(spacing: 5) {
                    Capsule().frame(width: 22, height: 2)
                    Capsule().frame(width: 22, height: 2)
                }
                .foregroundStyle(.primary)
            }

            // New chat
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
            }

            Spacer()

            // Mode + model picker — user avatar moved to the sidebar (ChatGPT/Claude style)
            ModeModelPicker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Sidebar Drawer

struct SidebarDrawer: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @Binding var isOpen: Bool
    let onOpenStorage: () -> Void
    let onOpenSettings: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var searchText = ""

    private let helpURL = URL(string: "https://docs.bluefunda.com/")!
    private let upgradeURL = URL(string: "https://cai.bluefunda.com/pricing")!

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return chatManager.conversations }
        return chatManager.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header: title + user avatar (top-right) ───
            HStack {
                Text("Chats")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    withAnimation { isOpen = false }
                    onOpenSettings()
                } label: {
                    Circle()
                        .fill(Color.brandBlue.gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(authManager.currentUser?.name.prefix(1).uppercased() ?? "U")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // New chat row
            Button {
                chatManager.newConversation()
                withAnimation { isOpen = false }
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("New Chat")
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations", text: $searchText)
                    .font(.subheadline)
            }
            .padding(8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // ── Conversation list ─────────────────────────
            if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredConversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(searchText.isEmpty ? "No conversations yet" : "No results")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groupedConversations) { group in
                            Text(group.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 2)

                            ForEach(group.conversations) { convo in
                                SidebarConversationRow(
                                    conversation: convo,
                                    isSelected: chatManager.currentConversation?.id == convo.id
                                )
                                .onTapGesture {
                                    chatManager.selectConversation(convo)
                                    withAnimation { isOpen = false }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()

            // ── Bottom nav ────────────────────────────────
            VStack(spacing: 0) {
                SidebarNavButton(icon: "externaldrive", label: "Cloud Storage") {
                    withAnimation { isOpen = false }
                    onOpenStorage()
                }

                SidebarNavButton(icon: "gear", label: "Settings") {
                    withAnimation { isOpen = false }
                    onOpenSettings()
                }

                SidebarNavButton(icon: "questionmark.circle", label: "Help & Support") {
                    withAnimation { isOpen = false }
                    onOpenURL(helpURL)
                }

                SidebarNavButton(icon: "crown", label: "Upgrade Plan") {
                    withAnimation { isOpen = false }
                    onOpenURL(upgradeURL)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 4, y: 0)
    }

    // Group conversations by recency
    private var groupedConversations: [ConversationGroup] {
        let now = Date()
        let cal = Calendar.current

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var older: [Conversation] = []

        for c in filteredConversations {
            let days = cal.dateComponents([.day], from: c.createdAt, to: now).day ?? 0
            if days == 0       { today.append(c) }
            else if days == 1  { yesterday.append(c) }
            else if days < 7   { thisWeek.append(c) }
            else               { older.append(c) }
        }

        var result: [ConversationGroup] = []
        if !today.isEmpty     { result.append(.init(title: "Today",     conversations: today)) }
        if !yesterday.isEmpty { result.append(.init(title: "Yesterday", conversations: yesterday)) }
        if !thisWeek.isEmpty  { result.append(.init(title: "This Week", conversations: thisWeek)) }
        if !older.isEmpty     { result.append(.init(title: "Older",     conversations: older)) }
        return result
    }
}

private struct ConversationGroup: Identifiable {
    let id: String      // == title, always unique within a list
    let title: String
    let conversations: [Conversation]

    init(title: String, conversations: [Conversation]) {
        self.id = title
        self.title = title
        self.conversations = conversations
    }
}

// MARK: - Sidebar Row

private struct SidebarConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(conversation.title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            isSelected
                ? Color.blue.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar Nav Button

private struct SidebarNavButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading…").foregroundStyle(.secondary)
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

                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)
                    Text("CAI")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Cognitive AI Interface")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Realm")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Realm", selection: $selectedRealm) {
                        ForEach(realms, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 40)

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
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                Spacer()

                Text("Powered by BlueFunda")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: BFFChatService()))
}
