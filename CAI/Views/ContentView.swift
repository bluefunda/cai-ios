import SwiftUI
import AuthenticationServices

extension Notification.Name {
    static let newChatRequested = Notification.Name("newChatRequested")
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        Group {
            if authManager.isRestoringSession || authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                AuthenticatedRoot()
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

// MARK: - Authenticated Root (Chat / </>Code mode switch)

struct AuthenticatedRoot: View {
    var body: some View { AppShell() }
}

// MARK: - App Shell (unified Chat + Code shell)

struct AppShell: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var iapManager: IAPManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("app_mode") private var modeRaw = AppMode.chat.rawValue
    @State private var sidebarOpen = false
    @State private var activeSheet: AppSheet?
    @State private var safariURL: URL?
    // .doubleColumn (not .automatic, and not .all — that's for 3-column
    // split views and made the system sidebar-toggle button disappear
    // entirely on our 2-column one). .automatic hands NavigationSplitView
    // discretion to re-decide visibility on its own, which on iPad/Mac was
    // silently collapsing the sidebar the moment the message field gained
    // focus (a focus-driven layout pass reads as a size-class change to
    // `.automatic`). .doubleColumn/.detailOnly are the two canonical states
    // the toggle button switches between for a 2-column split (cai-ios#256).
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    // Code mode
    @StateObject private var systemStore = SAPSystemStore()
    @State private var showSystems = false

    enum AppSheet: String, Identifiable {
        case storage, settings, subscription
        var id: String { rawValue }
    }

    private var mode: AppMode { AppMode(rawValue: modeRaw) ?? .chat }
    private var modeBinding: Binding<AppMode> {
        Binding(get: { mode }, set: { modeRaw = $0.rawValue })
    }

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(item: $activeSheet) { sheet in sheetView(sheet) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
        .sheet(isPresented: $showSystems) {
            SystemManagerView(store: systemStore).environmentObject(authManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            modeRaw = AppMode.chat.rawValue
            chatManager.newConversation()
        }
    }

    // MARK: - iPad: NavigationSplitView

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarContent(
                currentMode: modeBinding,
                onOpenStorage: { activeSheet = .storage },
                onOpenSettings: { activeSheet = .settings },
                onOpenSubscription: { activeSheet = .subscription },
                onOpenURL: { safariURL = $0 }
            )
            // Pin sidebar to a desktop-comfortable width; the detail column
            // gets the rest, which is where the 800-pt chat column lives.
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            // An empty title (Mac's actual window-title text is separately
            // hidden in CAIApp.swift) removes the redundant "BlueFunda AI"
            // that duplicated the sidebar's own header (cai-ios#253). The
            // sidebar toggle lives in the trailing group (not the leading
            // .navigation slot) — that slot's rendering turned out to depend
            // on undocumented Mac Catalyst chrome behavior (duplicated or got
            // buried under the sidebar depending on what else was declared
            // there); the trailing group never had that problem (cai-ios#256).
            //
            // Screenshot-confirmed behavior on Mac Catalyst (cai-ios#256):
            // Catalyst's native leading toggle only renders next to the
            // traffic lights while the sidebar column is COLLAPSED — it
            // disappears once the column is showing (its only job is
            // reopening a collapsed column). Our own SidebarToggleButton
            // sits in the trailing group and is always present, so while
            // collapsed both a native AND our own toggle show at once. Hide
            // ours specifically while collapsed so exactly one toggle is
            // ever visible: native for closed→open, ours for open→closed.
            content
                .navigationTitle(mode == .code ? "Code" : "")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        switch mode {
                        case .chat:
                            #if targetEnvironment(macCatalyst)
                            if columnVisibility != .detailOnly {
                                SidebarToggleButton(columnVisibility: $columnVisibility)
                            }
                            #else
                            SidebarToggleButton(columnVisibility: $columnVisibility)
                            #endif
                            AttachmentButton(conversationId: chatManager.currentConversation?.id)
                            NewChatButton(action: { chatManager.newConversation() })
                        case .code:
                            #if targetEnvironment(macCatalyst)
                            if columnVisibility != .detailOnly {
                                SidebarToggleButton(columnVisibility: $columnVisibility)
                            }
                            #else
                            SidebarToggleButton(columnVisibility: $columnVisibility)
                            #endif
                            Button(action: { showSystems = true }) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: BFFont.toolbarIconPt))
                            }
                        }
                    }
                }
                #if targetEnvironment(macCatalyst)
                .hidingNativeSplitViewToggle()
                #endif
        }
        // .balanced, not .prominentDetail: prominentDetail treats the sidebar
        // as a dismissible overlay above the detail content — it auto-hides
        // the moment you interact with the detail pane (tap New Chat, tap
        // into the chat), which read as "the sidebar won't stay open."
        // .balanced makes both genuine persistent columns; the sidebar's
        // width stays constrained by navigationSplitViewColumnWidth above so
        // the chat column still dominates the window (cai-ios#256).
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone: ZStack drawer

    private var iPhoneLayout: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                topBar
                content
            }
            .zIndex(0)

            if sidebarOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.25)) { sidebarOpen = false }
                    }
                    .zIndex(1)
                    .transition(.opacity)
            }

            SidebarDrawer(
                isOpen: $sidebarOpen,
                currentMode: modeBinding,
                onOpenStorage: { activeSheet = .storage },
                onOpenSettings: { activeSheet = .settings },
                onOpenSubscription: { activeSheet = .subscription },
                onOpenURL: { safariURL = $0 }
            )
            .frame(width: 300)
            .offset(x: sidebarOpen ? 0 : -310)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: sidebarOpen)
            .zIndex(2)
        }
        .animation(.default, value: sidebarOpen)
        .onChange(of: sidebarOpen) { _, open in
            if open {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        switch mode {
        case .chat:
            ChatTopBar(sidebarOpen: $sidebarOpen, onNewChat: { chatManager.newConversation() })
        case .code:
            CodeTopBar(sidebarOpen: $sidebarOpen, onSystems: { showSystems = true })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .chat:
            ChatView()
        case .code:
            CodeContent(systemStore: systemStore, onConnect: { showSystems = true })
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .storage: StorageView()
        case .settings:
            // Explicit re-injection: SettingsView's NavigationSplitView is
            // the root of this sheet, and on Mac Catalyst that split view's
            // sidebar column doesn't reliably inherit @EnvironmentObjects
            // only set at the WindowGroup level above the sheet presenter —
            // caused a "No ObservableObject of type AuthManager found"
            // crash on first open (cai-ios#254).
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(chatManager)
                .environmentObject(iapManager)
        case .subscription: SubscriptionView()
        }
    }
}

// MARK: - Sidebar Content (shared between iPad split view and iPhone drawer)

struct SidebarContent: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var iapManager: IAPManager
    @Binding var currentMode: AppMode
    let onOpenStorage: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSubscription: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var searchText = ""

    private let helpURL = URL(string: "https://docs.bluefunda.com/")!

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return chatManager.conversations }
        return chatManager.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Sidebar header: brand ────────
            // New Chat lives in the top toolbar (NewChatButton) now, not
            // duplicated here (cai-ios#256).
            HStack(spacing: 0) {
                Text("BlueFunda AI")
                    .font(BFFont.sidebarHeader)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations", text: $searchText)
                    .font(BFFont.sidebarItem)
            }
            .padding(8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredConversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(searchText.isEmpty ? "No conversations yet" : "No results")
                        .font(BFFont.sidebarItem)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groupedConversations) { group in
                            Text(group.title)
                                .font(BFFont.sidebarSection)
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
                                    currentMode = .chat
                                    chatManager.selectConversation(convo)
                                }
                                .accessibilityIdentifier("conversationRow")
                                .contextMenu {
                                    ShareLink(item: convo.markdownExport) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        chatManager.deleteConversation(convo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()

            VStack(spacing: 0) {
                SidebarNavButton(icon: "chevron.left.forwardslash.chevron.right", label: "Code") {
                    currentMode = .code
                }
            }

            Divider()

            // Upgrade to Pro — individual free users only
            if authManager.realm == "individual" && !iapManager.hasActiveSubscription {
                Button(action: onOpenSubscription) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Upgrade to Pro")
                            .font(BFFont.sidebarItemMed)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(BFColor.primaryTint, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BFColor.primary)
                .accessibilityIdentifier("upgradeToProButton")
            }

            // Profile row — bottom left, menu contains Settings + Help
            Menu {
                Button { onOpenSettings() } label: {
                    Label("Settings", systemImage: "gear")
                }
                if authManager.realm == "individual" {
                    Button { onOpenSubscription() } label: {
                        Label(
                            iapManager.hasActiveSubscription ? "Manage Subscription" : "Upgrade to Pro",
                            systemImage: iapManager.hasActiveSubscription ? "checkmark.seal" : "sparkles"
                        )
                    }
                }
                Button { onOpenURL(helpURL) } label: {
                    Label("Help & Support", systemImage: "questionmark.circle")
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(BFColor.primary.gradient)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Text(authManager.currentUser?.name.prefix(1).uppercased() ?? "U")
                                .font(BFFont.sidebarItemMed).foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(authManager.currentUser?.name ?? "Account")
                                .font(BFFont.sidebarItemMed)
                                .foregroundStyle(.primary).lineLimit(1)
                            if iapManager.hasActiveSubscription {
                                Text("Pro")
                                    .font(BFFont.micro.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BFColor.primary, in: Capsule())
                            }
                        }
                        if let email = authManager.currentUser?.email {
                            Text(email).font(BFFont.sidebarMeta).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileMenuButton")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

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

// MARK: - Hamburger

// MARK: - Sidebar Drawer

struct SidebarDrawer: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var iapManager: IAPManager
    @Binding var isOpen: Bool
    @Binding var currentMode: AppMode
    let onOpenStorage: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSubscription: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var searchText = ""

    private let helpURL = URL(string: "https://docs.bluefunda.com/")!

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return chatManager.conversations }
        return chatManager.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Sidebar header: brand + new chat ────────
            HStack(spacing: 0) {
                Text("BlueFunda AI")
                    .font(BFFont.sidebarHeader)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    currentMode = .chat
                    chatManager.newConversation()
                    withAnimation { isOpen = false }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: BFFont.toolbarIconPt - 2))
                        .foregroundStyle(BFColor.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations", text: $searchText)
                    .font(BFFont.sidebarItem)
            }
            .padding(8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // ── Conversation list ─────────────────────────
            if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredConversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(searchText.isEmpty ? "No conversations yet" : "No results")
                        .font(BFFont.sidebarItem)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groupedConversations) { group in
                            Text(group.title)
                                .font(BFFont.sidebarSection)
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
                                    currentMode = .chat
                                    chatManager.selectConversation(convo)
                                    withAnimation { isOpen = false }
                                }
                                .accessibilityIdentifier("conversationRow")
                                .contextMenu {
                                    ShareLink(item: convo.markdownExport) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        chatManager.deleteConversation(convo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
                SidebarNavButton(icon: "chevron.left.forwardslash.chevron.right", label: "Code") {
                    currentMode = .code
                    withAnimation { isOpen = false }
                }
            }

            Divider()

            // Upgrade to Pro — individual free users only
            if authManager.realm == "individual" && !iapManager.hasActiveSubscription {
                Button {
                    withAnimation { isOpen = false }
                    onOpenSubscription()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Upgrade to Pro")
                            .font(BFFont.sidebarItemMed)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(BFColor.primaryTint, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BFColor.primary)
                .accessibilityIdentifier("upgradeToProButton")
            }

            // Profile row — bottom left, menu contains Settings + Help
            Menu {
                Button {
                    withAnimation { isOpen = false }
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                if authManager.realm == "individual" {
                    Button {
                        withAnimation { isOpen = false }
                        onOpenSubscription()
                    } label: {
                        Label(
                            iapManager.hasActiveSubscription ? "Manage Subscription" : "Upgrade to Pro",
                            systemImage: iapManager.hasActiveSubscription ? "checkmark.seal" : "sparkles"
                        )
                    }
                }
                Button {
                    withAnimation { isOpen = false }
                    onOpenURL(helpURL)
                } label: {
                    Label("Help & Support", systemImage: "questionmark.circle")
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(BFColor.primary.gradient)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Text(authManager.currentUser?.name.prefix(1).uppercased() ?? "U")
                                .font(BFFont.sidebarItemMed).foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(authManager.currentUser?.name ?? "Account")
                                .font(BFFont.sidebarItemMed)
                                .foregroundStyle(.primary).lineLimit(1)
                            if iapManager.hasActiveSubscription {
                                Text("Pro")
                                    .font(BFFont.micro.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BFColor.primary, in: Capsule())
                            }
                        }
                        if let email = authManager.currentUser?.email {
                            Text(email).font(BFFont.sidebarMeta).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileMenuButton")
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

struct ConversationGroup: Identifiable {
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

struct SidebarConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(BFFont.sidebarSection)
                .foregroundStyle(.secondary)

            Text(conversation.title)
                .font(BFFont.sidebarItem)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            isSelected
                ? BFColor.primary.opacity(0.15)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar Nav Button

struct SidebarNavButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                    .font(BFFont.sidebarItem)
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
    @State private var logoTapCount = 0
    @State private var showRealmPicker = false
    @State private var appleSignInCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), BFColor.primaryTint],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(BFColor.primary.gradient)
                            .frame(width: 96, height: 96)
                            .bfShadow(BFShadow.lg)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundStyle(BFColor.textInverse)
                    }
                    .onTapGesture {
                        logoTapCount += 1
                        if logoTapCount >= 5 { showRealmPicker = true; logoTapCount = 0 }
                    }

                    VStack(spacing: 6) {
                        Text("BlueFunda")
                            .font(BFFont.h3)
                        Text("Your intelligent AI assistant")
                            .font(BFFont.bodySmall)
                            .foregroundStyle(BFColor.textTertiary)
                    }

                    VStack(spacing: 12) {
                        Text("Sign in to continue")
                            .font(BFFont.micro)
                            .foregroundStyle(BFColor.textTertiary)
                            .padding(.top, 14)
                            .padding(.bottom, 4)

                        SocialSignInButton(label: "Continue with Google", style: .outlined) {
                            authManager.login(realm: selectedRealm, idpHint: "google")
                        } icon: {
                            GoogleLogoView()
                        }

                        SocialSignInButton(label: "Continue with Microsoft", style: .outlined) {
                            authManager.login(realm: selectedRealm, idpHint: "azure")
                        } icon: {
                            MicrosoftLogoView()
                        }

                        SocialSignInButton(label: "Continue with Apple", style: .filled) {
                            let coordinator = AppleSignInCoordinator(realm: selectedRealm, authManager: authManager)
                            self.appleSignInCoordinator = coordinator
                            coordinator.start()
                        } icon: {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20))
                        }
                    }
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 4) {
                    if selectedRealm == "trm" {
                        Text("TRM")
                            .font(BFFont.micro)
                            .foregroundStyle(BFColor.textMuted)
                            .padding(.horizontal, BFSpacing._2)
                            .padding(.vertical, 2)
                            .background(BFColor.neutral100, in: Capsule())
                    }
                    Text("Powered by BlueFunda")
                        .font(BFFont.caption)
                        .foregroundStyle(BFColor.textMuted)
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                        .font(BFFont.micro)
                        .foregroundStyle(BFColor.textMuted.opacity(0.6))
                }
                .padding(.bottom, BFSpacing._8)
            }
        }
        .confirmationDialog("Select Realm", isPresented: $showRealmPicker) {
            Button("Individual") { selectedRealm = "individual" }
            Button("TRM") { selectedRealm = "trm" }
        }
        .alert("Error", isPresented: .constant(authManager.error != nil)) {
            Button("OK") { authManager.error = nil }
        } message: {
            Text(authManager.error?.localizedDescription ?? "")
        }
    }
}

private struct SocialSignInButton<Icon: View>: View {
    enum Style { case outlined, filled }

    let label: String
    let style: Style
    let action: () -> Void
    let icon: Icon

    init(label: String, style: Style, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.style = style
        self.action = action
        self.icon = icon()
    }

    private var backgroundColor: Color {
        style == .filled ? .black : Color(.systemBackground)
    }

    private var foregroundColor: Color {
        style == .filled ? .white : .primary
    }

    private var borderColor: Color {
        Color(.systemGray4)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(backgroundColor)
                if style == .outlined {
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                }

                HStack {
                    Spacer()

                    HStack(spacing: 12) {
                        icon
                            .frame(width: 22, height: 22)
                            .foregroundColor(foregroundColor)

                        Text(label)
                            .font(BFFont.idpButton)
                            .foregroundColor(foregroundColor)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .bfShadow(BFShadow.sm)
    }
}

private struct GoogleLogoView: View {
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 48
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 43.611 * scale, y: 20.083 * scale))
                    path.addLine(to: CGPoint(x: 42 * scale, y: 20 * scale))
                    path.addLine(to: CGPoint(x: 24 * scale, y: 20 * scale))
                    path.addLine(to: CGPoint(x: 24 * scale, y: 28 * scale))
                    path.addLine(to: CGPoint(x: 35.303 * scale, y: 28 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 36 * scale),
                        control1: CGPoint(x: 33.654 * scale, y: 32.657 * scale),
                        control2: CGPoint(x: 29.223 * scale, y: 36 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 12 * scale, y: 24 * scale),
                        control1: CGPoint(x: 17.676 * scale, y: 36 * scale),
                        control2: CGPoint(x: 12 * scale, y: 30.627 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 12 * scale),
                        control1: CGPoint(x: 12 * scale, y: 17.373 * scale),
                        control2: CGPoint(x: 17.373 * scale, y: 12 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 31.961 * scale, y: 15.039 * scale),
                        control1: CGPoint(x: 27.059 * scale, y: 12 * scale),
                        control2: CGPoint(x: 29.842 * scale, y: 13.154 * scale)
                    )
                    path.addLine(to: CGPoint(x: 37.618 * scale, y: 9.382 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 4 * scale),
                        control1: CGPoint(x: 34.046 * scale, y: 6.053 * scale),
                        control2: CGPoint(x: 29.268 * scale, y: 4 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 4 * scale, y: 24 * scale),
                        control1: CGPoint(x: 12.955 * scale, y: 4 * scale),
                        control2: CGPoint(x: 4 * scale, y: 12.955 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 44 * scale),
                        control1: CGPoint(x: 4 * scale, y: 35.045 * scale),
                        control2: CGPoint(x: 12.955 * scale, y: 44 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 44 * scale, y: 24 * scale),
                        control1: CGPoint(x: 35.045 * scale, y: 44 * scale),
                        control2: CGPoint(x: 44 * scale, y: 35.045 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 43.611 * scale, y: 20.083 * scale),
                        control1: CGPoint(x: 44 * scale, y: 22.659 * scale),
                        control2: CGPoint(x: 43.862 * scale, y: 21.35 * scale)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 1, green: 0.756, blue: 0.027))

                Path { path in
                    path.move(to: CGPoint(x: 6.306 * scale, y: 14.691 * scale))
                    path.addLine(to: CGPoint(x: 12.877 * scale, y: 19.51 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 12 * scale),
                        control1: CGPoint(x: 14.655 * scale, y: 15.108 * scale),
                        control2: CGPoint(x: 18.961 * scale, y: 12 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 31.961 * scale, y: 15.039 * scale),
                        control1: CGPoint(x: 27.059 * scale, y: 12 * scale),
                        control2: CGPoint(x: 29.842 * scale, y: 13.154 * scale)
                    )
                    path.addLine(to: CGPoint(x: 37.618 * scale, y: 9.382 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 4 * scale),
                        control1: CGPoint(x: 34.046 * scale, y: 6.053 * scale),
                        control2: CGPoint(x: 29.268 * scale, y: 4 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 6.306 * scale, y: 14.691 * scale),
                        control1: CGPoint(x: 16.318 * scale, y: 4 * scale),
                        control2: CGPoint(x: 9.656 * scale, y: 8.337 * scale)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 1, green: 0.239, blue: 0))

                Path { path in
                    path.move(to: CGPoint(x: 24 * scale, y: 44 * scale))
                    path.addCurve(
                        to: CGPoint(x: 37.409 * scale, y: 38.808 * scale),
                        control1: CGPoint(x: 29.166 * scale, y: 44 * scale),
                        control2: CGPoint(x: 33.86 * scale, y: 42.023 * scale)
                    )
                    path.addLine(to: CGPoint(x: 31.219 * scale, y: 33.57 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 36 * scale),
                        control1: CGPoint(x: 29.211 * scale, y: 35.091 * scale),
                        control2: CGPoint(x: 26.715 * scale, y: 36 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 12.717 * scale, y: 28.054 * scale),
                        control1: CGPoint(x: 18.798 * scale, y: 36 * scale),
                        control2: CGPoint(x: 14.381 * scale, y: 32.683 * scale)
                    )
                    path.addLine(to: CGPoint(x: 6.195 * scale, y: 33.079 * scale))
                    path.addCurve(
                        to: CGPoint(x: 24 * scale, y: 44 * scale),
                        control1: CGPoint(x: 9.505 * scale, y: 39.556 * scale),
                        control2: CGPoint(x: 16.227 * scale, y: 44 * scale)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 0.298, green: 0.737, blue: 0.318))

                Path { path in
                    path.move(to: CGPoint(x: 43.611 * scale, y: 20.083 * scale))
                    path.addLine(to: CGPoint(x: 42 * scale, y: 20 * scale))
                    path.addLine(to: CGPoint(x: 24 * scale, y: 20 * scale))
                    path.addLine(to: CGPoint(x: 24 * scale, y: 28 * scale))
                    path.addLine(to: CGPoint(x: 35.303 * scale, y: 28 * scale))
                    path.addCurve(
                        to: CGPoint(x: 31.216 * scale, y: 33.571 * scale),
                        control1: CGPoint(x: 34.511 * scale, y: 32.237 * scale),
                        control2: CGPoint(x: 33.072 * scale, y: 34.166 * scale)
                    )
                    path.addLine(to: CGPoint(x: 37.406 * scale, y: 38.809 * scale))
                    path.addCurve(
                        to: CGPoint(x: 44 * scale, y: 24 * scale),
                        control1: CGPoint(x: 36.971 * scale, y: 39.205 * scale),
                        control2: CGPoint(x: 44 * scale, y: 34 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 43.611 * scale, y: 20.083 * scale),
                        control1: CGPoint(x: 44 * scale, y: 22.659 * scale),
                        control2: CGPoint(x: 43.862 * scale, y: 21.35 * scale)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 0.098, green: 0.463, blue: 0.824))
            }
        }
    }
}

private struct MicrosoftLogoView: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Color(red: 1, green: 87/255, blue: 34/255)
                Color(red: 76/255, green: 175/255, blue: 80/255)
            }
            HStack(spacing: 2) {
                Color(red: 3/255, green: 169/255, blue: 244/255)
                Color(red: 1, green: 193/255, blue: 7/255)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Apple Sign In Coordinator

private class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var nonce: (plain: String, hashed: String)?
    private var realm: String
    private var authManager: AuthManager

    init(realm: String, authManager: AuthManager) {
        self.realm = realm
        self.authManager = authManager
        super.init()
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let noncePair = makeAuthNonce()
        self.nonce = noncePair
        request.nonce = noncePair?.hashed

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let plain = nonce?.plain
        nonce = nil
        Task {
            await authManager.handleAppleAuthorization(
                authorization,
                realm: realm,
                nonce: plain
            )
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        nonce = nil
        if (error as? ASAuthorizationError)?.code != .canceled {
            authManager.error = .authenticationFailed(error.localizedDescription)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: BFFChatService()))
}