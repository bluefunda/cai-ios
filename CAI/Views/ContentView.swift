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

// MARK: - Authenticated Root

struct AuthenticatedRoot: View {
    var body: some View { AppShell() }
}

// MARK: - App Shell
// Space → Destination navigation (docs/BLUEREQUESTS_INTEGRATION.md P2): one SidebarView,
// presented as a persistent split-view column on iPad/Mac or an overlay drawer on iPhone,
// and the current destination in the detail area. The current space and destination live
// in WorkspaceStore, persisted per space.

struct AppShell: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var iapManager: IAPManager
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.horizontalSizeClass) private var sizeClass

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
    @FocusState private var sidebarSearchFocused: Bool

    // Code destination
    @StateObject private var systemStore = SAPSystemStore()
    @State private var showSystems = false

    enum AppSheet: String, Identifiable {
        case settings, subscription
        var id: String { rawValue }
    }

    private var destination: SidebarDestination { workspace.currentDestination }
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background {
            ShellKeyboardShortcuts(
                onDestination: { workspace.navigate(to: .assistant($0)) },
                onFocusSearch: focusSidebarSearch
            )
        }
        .sheet(item: $activeSheet) { sheet in sheetView(sheet) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
        .sheet(isPresented: $showSystems) {
            SystemManagerView(store: systemStore).environmentObject(authManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            workspace.navigate(to: .assistant(.chats))
            chatManager.newConversation()
        }
    }

    private func sidebar(_ presentation: SidebarPresentation) -> some View {
        SidebarView(
            presentation: presentation,
            systemStore: systemStore,
            searchFocus: $sidebarSearchFocused,
            onOpenSettings: { activeSheet = .settings },
            onOpenSubscription: { activeSheet = .subscription },
            onOpenURL: { safariURL = $0 },
            onManageSystems: { showSystems = true }
        )
    }

    // MARK: - iPad: NavigationSplitView

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(.split(columnVisibility: $columnVisibility))
                #if targetEnvironment(macCatalyst)
                .toolbar(removing: .sidebarToggle)
                .hidingNativeSplitViewToggle()
                #endif
                // Pin sidebar to a desktop-comfortable width; the detail column
                // gets the rest, which is where the 800-pt chat column lives.
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            // An empty title (Mac's actual window-title text is separately
            // hidden in CAIApp.swift) removes the redundant "BlueFunda AI"
            // that duplicated the sidebar's own header (cai-ios#253).
            content(navigationControl: splitNavigationControl)
                .navigationTitle(destination == .assistant(.code) ? "Code" : "")
                .toolbar {
                    // The shell's single toolbar group, per destination. Files, Agents
                    // and Requests own a NavigationStack and place their controls inside
                    // it (see ShellNavigationControl).
                    ToolbarItemGroup(placement: .primaryAction) {
                        switch destination {
                        case .assistant(.chats):
                            #if targetEnvironment(macCatalyst)
                            SidebarToggleButton(columnVisibility: $columnVisibility)
                            #endif
                            AttachmentButton(conversationId: chatManager.currentConversation?.id)
                            NewChatButton(action: { chatManager.newConversation() })
                        case .assistant(.code):
                            #if targetEnvironment(macCatalyst)
                            SidebarToggleButton(columnVisibility: $columnVisibility)
                            #endif
                            Button(action: { showSystems = true }) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: BFFont.toolbarIconPt))
                            }
                            .accessibilityLabel("SAP systems")
                            .bfPointerHover()
                        case .assistant(.files), .assistant(.agents), .requests:
                            EmptyView()
                        }
                    }
                }
                #if targetEnvironment(macCatalyst)
                .toolbar(removing: .sidebarToggle)
                .hidingNativeSplitViewToggle()
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .toolbar(removing: .sidebarToggle)
        #endif
        // .balanced, not .prominentDetail: prominentDetail treats the sidebar
        // as a dismissible overlay above the detail content — it auto-hides
        // the moment you interact with the detail pane (tap New Chat, tap
        // into the chat), which read as "the sidebar won't stay open."
        // .balanced makes both genuine persistent columns; the sidebar's
        // width stays constrained by navigationSplitViewColumnWidth above so
        // the chat column still dominates the window (cai-ios#256).
        .navigationSplitViewStyle(.balanced)
    }

    /// Mac Catalyst keeps its sidebar toggle in the detail toolbar (the sidebar header
    /// can't host it there); iPad's lives in the sidebar header instead.
    private var splitNavigationControl: ShellNavigationControl {
        #if targetEnvironment(macCatalyst)
        return .sidebarToggle(columnVisibility: $columnVisibility)
        #else
        return .none
        #endif
    }

    // MARK: - iPhone: ZStack drawer

    private var iPhoneLayout: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                topBar
                content(navigationControl: .drawer(isOpen: $sidebarOpen))
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

            sidebar(.drawer(isOpen: $sidebarOpen))
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

    /// Chats and Code draw their own compact bar; the destinations that own a
    /// NavigationStack get the hamburger in their navigation bar instead.
    @ViewBuilder
    private var topBar: some View {
        switch destination {
        case .assistant(.chats):
            ChatTopBar(sidebarOpen: $sidebarOpen, onNewChat: { chatManager.newConversation() })
        case .assistant(.code):
            CodeTopBar(sidebarOpen: $sidebarOpen, onSystems: { showSystems = true })
        case .assistant(.files), .assistant(.agents), .requests:
            EmptyView()
        }
    }

    // MARK: - Destination Content

    @ViewBuilder
    private func content(navigationControl: ShellNavigationControl) -> some View {
        switch destination {
        case .assistant(.chats):
            ChatView()
        case .assistant(.code):
            CodeContent(systemStore: systemStore, onConnect: { showSystems = true })
        case .assistant(.files):
            StorageView(navigationControl: navigationControl)
        case .assistant(.agents):
            NavigationStack {
                AgentsListView()
                    .shellNavigationControl(navigationControl)
            }
        case .requests(let requestsDestination):
            RequestsPlaceholderView(destination: requestsDestination, navigationControl: navigationControl)
        }
    }

    // MARK: - Keyboard

    /// ⌘F: jump to Chats, show the sidebar, then focus its search field once the
    /// sidebar is on screen to receive focus.
    private func focusSidebarSearch() {
        workspace.navigate(to: .assistant(.chats))
        if isRegular {
            withAnimation { columnVisibility = .doubleColumn }
        } else {
            withAnimation(.spring(duration: 0.25)) { sidebarOpen = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            sidebarSearchFocused = true
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
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

    /// textTertiary in light mode; a lighter grey in dark mode so the subtitle and policy line
    /// stay readable on the dark navy gradient.
    private let secondaryText = Color(lightHex: "#5A5A5A", darkHex: "#9CA3AF")

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
                            .foregroundStyle(secondaryText)
                    }

                    VStack(spacing: 12) {
                        Text("Sign in to continue")
                            .font(BFFont.micro)
                            .foregroundStyle(secondaryText)
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

                        // Policies must be reachable before sign-in (App Store privacy rules).
                        Text("By continuing, you agree to our [Terms\u{00A0}of\u{00A0}Service](https://bluefunda.com/terms/) and [Privacy\u{00A0}Policy](https://bluefunda.com/privacy/).")
                            .font(BFFont.micro)
                            .foregroundStyle(secondaryText)
                            .tint(BFColor.primary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
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
        .bfPointerHover()
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