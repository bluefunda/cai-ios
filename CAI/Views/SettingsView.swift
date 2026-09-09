import SwiftUI
import UIKit

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case account, aiSettings, usage, subscription, legal, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .aiSettings: return "AI Settings"
        case .usage: return "Usage"
        case .subscription: return "Subscription"
        case .legal: return "Legal"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .aiSettings: return "sparkles"
        case .usage: return "chart.bar"
        case .subscription: return "star.circle"
        case .legal: return "doc.text"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    // nil (not .account) so opening Settings on a compact/iPhone layout shows the category
    // list first instead of auto-navigating straight into Account — detailContent below still
    // falls back to .account for the regular/split-view detail pane, which always needs
    // something to show even with no explicit selection.
    @State private var selectedCategory: SettingsCategory?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    // Internal infra details (Connection, Build) are only shown to the
    // internal/employee realm; end users on `individual` don't see them.
    private var isTrmRealm: Bool { authManager.realm == "trm" }
    private var isIndividualRealm: Bool { authManager.realm == "individual" }

    // Temporarily hidden (2026-08-07) — re-enable in a few days. Flip back
    // to true rather than re-adding the row.
    private let assistantRowEnabled = false

    private var assistantsSummary: String {
        let enabled = chatManager.visibleMCPServers.filter { chatManager.enabledMCPServers.contains($0.id) }
        if enabled.isEmpty { return "None" }
        if enabled.count == 1 { return enabled[0].displayName }
        return "\(enabled.count) Selected"
    }

    // Subscription is individual-realm only — trm accounts don't buy IAP.
    private var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0 != .subscription || isIndividualRealm }
    }

    // Percentage-of-screen sizing (~ Copilot's desktop Settings window: about
    // half the screen's width, three-quarters of its height) so the sheet
    // reads as a real preferences window instead of a cramped default sheet.
    // iPhone (compact width) is left alone — full-sheet there is correct.
    private var screenSize: CGSize {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size
            ?? CGSize(width: 1200, height: 800)
    }

    private var categoryList: some View {
        List(selection: $selectedCategory) {
            ForEach(categories) { category in
                HStack {
                    Label(category.title, systemImage: category.icon)
                    Spacer()
                    // The sidebar list style (automatic here, as the first content of
                    // NavigationSplitView) doesn't draw a disclosure chevron on its own —
                    // sidebar rows are selection rows, not NavigationLinks. Added explicitly
                    // to match cai-android's ChevronRight on each Settings row.
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .bfPointerHover()
                .tag(category)
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if sizeClass == .regular {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Settings")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        SidebarToggleButton(columnVisibility: $columnVisibility)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    categoryList
                        .listStyle(.sidebar)
                }
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(removing: .sidebarToggle)
                .background(PreventSplitViewToggle())
            } else {
                categoryList
                    .navigationTitle("Settings")
            }
        } detail: {
            NavigationStack {
                detailContent
                    .toolbar(removing: .sidebarToggle)
                    .background(PreventSplitViewToggle())
            }
            // Resets any pushed sub-page (e.g. Default Persona) when the
            // user switches categories, matching macOS System Settings.
            .id(selectedCategory)
        }
        .toolbar(removing: .sidebarToggle)
        .background(PreventSplitViewToggle())
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topLeading) {
            if columnVisibility == .detailOnly {
                Button {
                    withAnimation {
                        columnVisibility = .doubleColumn
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: BFFont.toolbarIconPt))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .bfPointerHover()
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        // This sheet has no OS-provided close chrome to fall back on — iPhone gets away with no
        // explicit button because swipe-to-dismiss covers it, but Mac Catalyst has no such
        // gesture, so without this the sheet was stuck open with no way to close it. A manual
        // overlay instead of .toolbar: a ToolbarItem attached to the sidebar column only pinned to
        // that column's own (narrower) trailing edge, not the window's; attached to the whole
        // NavigationSplitView instead, it didn't render at all in this Mac Catalyst sheet context
        // — NavigationSplitView itself doesn't host a toolbar surface, only its columns do. An
        // overlay sidesteps both by positioning directly against this view's own frame.
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                // No explicit foregroundStyle — SidebarToggleButton (the "match this" reference)
                // has none either and just inherits the default accent/tint color; giving this an
                // explicit BFColor.primary was a close-but-not-quite shade of the same blue.
                Image(systemName: "xmark")
                    .font(.system(size: BFFont.toolbarIconPt - 4))
                    // Widens the actual tappable area well past the small glyph itself, without
                    // changing how it looks — a plain icon with no background is an easy miss
                    // otherwise, especially with a mouse cursor rather than a fingertip.
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .bfPointerHover()
            // Without this, Mac Catalyst applies its default bordered-button chrome (rounded
            // box + shadow) since this isn't hosted in a .toolbar the way the chat toolbar's
            // icon-only buttons are — .plain strips that back down to just the icon.
            .buttonStyle(.plain)
            .padding(16)
        }
        .frame(
            minWidth: sizeClass == .regular ? 640 : nil,
            idealWidth: sizeClass == .regular ? min(max(screenSize.width * 0.55, 640), 960) : nil,
            maxWidth: sizeClass == .regular ? 960 : nil,
            minHeight: sizeClass == .regular ? 560 : nil,
            idealHeight: sizeClass == .regular ? min(max(screenSize.height * 0.75, 560), 900) : nil,
            maxHeight: sizeClass == .regular ? 900 : nil
        )
        .confirmationDialog("Sign Out", isPresented: $showLogoutConfirmation) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await chatManager.disconnect()
                    await authManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and data. This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory ?? .account {
        case .account: accountDetail
        case .aiSettings: aiSettingsDetail
        case .usage: usageDetail
        case .subscription: subscriptionDetail
        case .legal: legalDetail
        case .about: aboutDetail
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountDetail: some View {
        List {
            Section {
                if let user = authManager.currentUser {
                    UserInfoRow(user: user)
                }
            }

            Section {
                Button {
                    openURL(reportContentURL)
                } label: {
                    HStack {
                        Label("Report Suspicious Content", systemImage: "flag")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .bfPointerHover()
            } footer: {
                Text("Report content within the app that you believe is suspicious, abusive, or violates our policies. This opens an email to our support team.")
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .bfPointerHover()
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete Account")
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .disabled(isDeleting)
                .bfPointerHover()
            } footer: {
                Text("Permanently deletes your account and all associated data. This can't be undone.")
            }
        }
        .navigationTitle("Account")
    }

    // MARK: - AI Settings

    @ViewBuilder
    private var aiSettingsDetail: some View {
        List {
            Section {
                if assistantRowEnabled {
                    NavigationLink {
                        MCPServerSelectionView()
                    } label: {
                        HStack {
                            Label("Assistant", systemImage: "sparkles")
                            Spacer()
                            Text(assistantsSummary)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .bfPointerHover()
                }

                Toggle(isOn: $chatManager.personaEnabled) {
                    Label("SAP Persona", systemImage: "person.text.rectangle")
                }
                .bfPointerHover()

                NavigationLink {
                    PersonaSelectionView()
                } label: {
                    HStack {
                        Label("Default Persona", systemImage: chatManager.persona.icon)
                        Spacer()
                        Text(chatManager.persona.label)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .disabled(!chatManager.personaEnabled)
                .opacity(chatManager.personaEnabled ? 1 : 0.4)
                .bfPointerHover()
            } footer: {
                Text("Tunes terminology and depth to your SAP specialty. Turn off to use the assistant with no persona.")
            }
        }
        .navigationTitle("AI Settings")
    }

    // MARK: - Usage

    // Embeds RateLimitView's content directly (no intermediate summary screen to tap
    // through first) — matches cai-android's flat Settings -> Usage navigation.
    @ViewBuilder
    private var usageDetail: some View {
        RateLimitView()
    }

    // MARK: - Subscription

    // Embeds SubscriptionContent directly (no dismiss chrome, no NavigationStack of its
    // own) — matches cai-android's flat Settings -> Subscription navigation instead of
    // pushing through an extra "Upgrade to Pro / Free >" summary row first.
    @ViewBuilder
    private var subscriptionDetail: some View {
        SubscriptionContent()
    }

    // MARK: - Legal

    @ViewBuilder
    private var legalDetail: some View {
        List {
            Section {
                Button {
                    openURL(privacyPolicyURL)
                } label: {
                    HStack {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .bfPointerHover()

                Button {
                    openURL(termsOfServiceURL)
                } label: {
                    HStack {
                        Label("Terms of Service", systemImage: "doc.text")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .bfPointerHover()
            }
        }
        .navigationTitle("Legal")
    }

    // MARK: - About

    @ViewBuilder
    private var aboutDetail: some View {
        List {
            Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundColor(.secondary)
                }
            }

            // Internal infra detail — trm realm only.
            if isTrmRealm {
                Section {
                    HStack {
                        Label("Status", systemImage: statusIcon)
                        Spacer()
                        Text(chatManager.connectionStatus.description)
                            .foregroundColor(statusColor)
                    }

                    HStack {
                        Label("Service", systemImage: "network")
                        Spacer()
                        Text("BFF (api.bluefunda.com/ai)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Using cai-gw/cai-bff HTTP SSE endpoints.")
                }
            }
        }
        .navigationTitle("About")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    private let privacyPolicyURL = URL(string: "https://bluefunda.com/privacy/")!
    private let termsOfServiceURL = URL(string: "https://bluefunda.com/terms/")!

    private var reportContentURL: URL {
        let subject = "Report Suspicious Content - CAI iOS App"
        var body = "Please describe the content you'd like to report and where you encountered it (e.g. chat message, conversation title):\n\n\n"
        if let email = authManager.currentUser?.email {
            body += "—\nAccount: \(email)"
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body

        return URL(string: "mailto:info@bluefunda.com?subject=\(encodedSubject)&body=\(encodedBody)")
            ?? URL(string: "mailto:info@bluefunda.com")!
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                await chatManager.disconnect()
                try await authManager.deleteAccount()
                // On success, isAuthenticated flips to false → routes to LoginView.
            } catch {
                deleteError = error.localizedDescription
            }
            isDeleting = false
        }
    }

    private var statusIcon: String {
        switch chatManager.connectionStatus {
        case .connected:
            return "wifi"
        case .connecting, .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch chatManager.connectionStatus {
        case .connected:
            return BFColor.success
        case .connecting, .reconnecting:
            return BFColor.warning
        case .error:
            return BFColor.error
        case .disconnected:
            return BFColor.neutral400
        }
    }
}

// MARK: - User Info Row

struct UserInfoRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(BFColor.primary.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(user.name.prefix(1).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(BFColor.textInverse)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.headline)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if user.isAdmin {
                    Text("ADMIN")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BFColor.warningBg)
                        .foregroundColor(BFColor.warning)
                        .cornerRadius(BFRadius.sm)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MCP Server Selection View

struct MCPServerSelectionView: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        List {
            Section {
                ForEach(chatManager.visibleMCPServers) { server in
                    Button {
                        toggle(server)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.displayName)
                                    .foregroundColor(.primary)
                                    .fontWeight(isSelected(server) ? .semibold : .regular)
                            }

                            Spacer()

                            if isSelected(server) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(BFColor.primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .bfPointerHover()
                }
            } footer: {
                Text("Enable one or more assistants to make their tools available in chat.")
            }
        }
        .navigationTitle("Assistants")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if chatManager.visibleMCPServers.isEmpty {
                ContentUnavailableView(
                    "No Assistants",
                    systemImage: "sparkles",
                    description: Text("No assistants are configured for your account.")
                )
            }
        }
    }

    private func toggle(_ server: MCPServer) {
        if chatManager.enabledMCPServers.contains(server.id) {
            chatManager.enabledMCPServers.remove(server.id)
        } else {
            chatManager.enabledMCPServers.insert(server.id)
        }
    }

    private func isSelected(_ server: MCPServer) -> Bool {
        chatManager.enabledMCPServers.contains(server.id)
    }
}

// MARK: - Persona Selection View

struct PersonaSelectionView: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        List {
            Section {
                // "General" (no SAP focus) isn't offered as a Default Persona
                // choice — it's only reachable in-chat via the composer's
                // SAP Persona toggle being off.
                ForEach(chatManager.availablePersonas) { persona in
                    Button {
                        chatManager.persona = persona
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(persona.label)
                                        .foregroundColor(.primary)
                                        .fontWeight(chatManager.persona == persona ? .semibold : .regular)
                                    Text(persona.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: persona.icon)
                            }

                            Spacer()

                            if chatManager.persona == persona {
                                Image(systemName: "checkmark")
                                    .foregroundColor(BFColor.primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .bfPointerHover()
                }
            } footer: {
                Text("Used to tune terminology and depth in chat responses.")
            }
        }
        .navigationTitle("SAP Persona")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Split View Configurator (iPad/Mac)

private struct PreventSplitViewToggle: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SplitConfigViewController {
        SplitConfigViewController()
    }

    func updateUIViewController(_ uiViewController: SplitConfigViewController, context: Context) {
        uiViewController.configureSplit()
    }
}

private class SplitConfigViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureSplit()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureSplit()
        for delay in [0.05, 0.1, 0.2, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.configureSplit()
            }
        }
    }

    func configureSplit() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap { $0.windows }

            for window in windows {
                if let root = window.rootViewController {
                    self.processVC(root)
                }
                self.hideSidebarViews(in: window)
            }
        }
    }

    private func processVC(_ vc: UIViewController) {
        if let split = vc as? UISplitViewController {
            split.displayModeButtonVisibility = .never
            split.presentsWithGesture = false
            split.displayModeButtonItem.isEnabled = false
            split.displayModeButtonItem.image = nil
            split.displayModeButtonItem.title = nil
            hideSidebarViews(in: split.view)
        }
        for child in vc.children {
            processVC(child)
        }
        if let presented = vc.presentedViewController {
            processVC(presented)
        }
    }

    private func hideSidebarViews(in view: UIView) {
        for subview in view.subviews {
            let className = String(describing: type(of: subview))
            if className.contains("SidebarButton") ||
               className.contains("DisplayMode") ||
               className.contains("SplitButton") ||
               className.contains("SidebarToggle") {
                subview.isHidden = true
                subview.alpha = 0
            }
            if let button = subview as? UIButton {
                let btnClass = String(describing: type(of: button))
                if btnClass.contains("Sidebar") || btnClass.contains("DisplayMode") {
                    button.isHidden = true
                    button.alpha = 0
                }
            }
            if let imgView = subview as? UIImageView,
               let img = imgView.image,
               img.description.contains("sidebar") {
                let rect = subview.convert(subview.bounds, to: nil)
                if rect.origin.y > 150 {
                    subview.isHidden = true
                    subview.alpha = 0
                    if let parent = subview.superview, !(parent is UIWindow) {
                        let parentClass = String(describing: type(of: parent))
                        if !parentClass.contains("Hosting") {
                            parent.isHidden = true
                            parent.alpha = 0
                        }
                    }
                }
            }
            hideSidebarViews(in: subview)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: NATSChatService()))
        .environmentObject(IAPManager())
}
