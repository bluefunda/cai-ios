import SwiftUI

// MARK: - Sidebar
// One sidebar for every platform (docs/BLUEREQUESTS_INTEGRATION.md P3), replacing the
// old SidebarContent (iPad/Mac split view) + SidebarDrawer (iPhone overlay) pair, which
// had drifted apart. Layers, top to bottom:
//
//   1  header        brand, plus the sidebar toggle (iPad) or New Chat (iPhone drawer)
//   2  space switch  Assistant | Requests — only when the user has both (P2)
//   3a destinations  fixed rows for the active space
//   3b context       what belongs to the destination: chat history, SAP systems, …
//   4  footer        upgrade pill + profile row with the org chip
//
// The two presentations differ only in what happens around an action: the drawer
// closes itself first, and for a conversation it waits for that animation to finish
// before binding (see `selectConversation`).

enum SidebarPresentation {
    /// iPad / Mac: the persistent NavigationSplitView column.
    case split(columnVisibility: Binding<NavigationSplitViewVisibility>)
    /// iPhone: the ZStack overlay drawer.
    case drawer(isOpen: Binding<Bool>)

    var isDrawer: Bool {
        if case .drawer = self { return true }
        return false
    }
}

struct SidebarView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var iapManager: IAPManager
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var unreadPoller: UnreadCountPoller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: SidebarPresentation
    @ObservedObject var systemStore: SAPSystemStore
    @ObservedObject var requestsState: RequestsState
    var searchFocus: FocusState<Bool>.Binding
    let onOpenSettings: () -> Void
    let onOpenSubscription: () -> Void
    let onOpenURL: (URL) -> Void
    let onManageSystems: () -> Void

    private let helpURL = URL(string: "https://docs.bluefunda.com/")!

    var body: some View {
        let layout = SidebarLayout(workspace: workspace)
        VStack(spacing: 0) {
            header

            if layout.showsSpaceSwitcher {
                SpaceSwitcher(
                    spaces: layout.spaces,
                    selection: layout.activeSpace,
                    badges: spaceBadges(active: layout.activeSpace)
                ) { space in
                    switchSpace(to: space)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            // 3a + 3b swap as one unit when the space changes, so the cross-fade
            // (P13 motion) reads as one move rather than two.
            VStack(spacing: 0) {
                destinationRows(layout.destinations)
                BFHairline()
                contextList
            }
            .id(layout.activeSpace)
            .transition(.opacity)

            BFHairline()
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BFColor.surfaceSidebar)
        .modifier(PresentationChrome(presentation: presentation))
    }

    // MARK: - 1 Header

    private var header: some View {
        // New Chat lives in the top toolbar (NewChatButton) on iPad/Mac, not
        // duplicated here (cai-ios#256). The sidebar-collapse toggle lives here
        // (not the detail pane's own toolbar) so there's exactly one control for
        // it, not two — except on Mac Catalyst, where it sits in the detail
        // toolbar instead.
        HStack(spacing: 0) {
            Text("BlueFunda AI")
                .font(BFFont.sidebarHeader)
                .foregroundStyle(.primary)
            Spacer()
            #if !targetEnvironment(macCatalyst)
            if case .split(let columnVisibility) = presentation {
                SidebarToggleButton(columnVisibility: columnVisibility)
            }
            #endif
            if presentation.isDrawer {
                Button {
                    workspace.navigate(to: .assistant(.chats))
                    chatManager.newConversation()
                    closeDrawer()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: BFFont.toolbarIconPt - 2))
                        .foregroundStyle(BFColor.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
                .accessibilityIdentifier("sidebar.newChat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - 3a Destinations

    private func destinationRows(_ destinations: [SidebarDestination]) -> some View {
        VStack(spacing: 2) {
            ForEach(destinations) { destination in
                SidebarDestinationRow(
                    destination: destination,
                    isSelected: workspace.currentDestination == destination,
                    badge: destination == .requests(.requests) ? unreadCount : 0
                ) {
                    workspace.navigate(to: destination)
                    closeDrawer()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - 3b Context

    @ViewBuilder
    private var contextList: some View {
        switch workspace.currentDestination {
        case .assistant(.chats):
            SidebarConversationList(
                allowsSwipeActions: presentation.isDrawer,
                searchFocus: searchFocus,
                onStartChat: {
                    workspace.navigate(to: .assistant(.chats))
                    chatManager.newConversation()
                    closeDrawer()
                },
                onSelect: selectConversation
            )
            .padding(.top, 10)
        case .assistant(.code):
            SidebarSystemsList(store: systemStore) {
                closeDrawer()
                onManageSystems()
            } onSelect: { _ in
                closeDrawer()
            }
        case .requests(.requests):
            RequestsSidebarList(
                state: requestsState,
                recents: requestsState.recents
            ) { filter in
                workspace.navigate(to: .requests(.requests))
                requestsState.requestsPath = []
                requestsState.changeRequests?.apply(filter)
                closeDrawer()
            } onOpenRecent: { recent in
                workspace.navigate(to: .requests(.requests))
                requestsState.openRequest(id: recent.id)
                closeDrawer()
            }
        case .assistant(.files), .assistant(.agents), .requests:
            Spacer(minLength: 0)
        }
    }

    // MARK: - Badges (P9)

    /// Unread Requests activity. Zero unless the Requests space is available — the poller
    /// never runs (and clears its counts) otherwise, so no badge for a space the user
    /// can't open.
    private var unreadCount: Int {
        guard workspace.isRequestsAvailable else { return 0 }
        return unreadPoller.counts?.totalUnreadMessages ?? 0
    }

    /// The Requests segment carries the count only while the user is in the other space;
    /// inside Requests, the Requests row shows it instead.
    private func spaceBadges(active: AppSpace) -> [AppSpace: Int] {
        active == .requests ? [:] : [.requests: unreadCount]
    }

    private func selectConversation(_ convo: Conversation) {
        workspace.navigate(to: .assistant(.chats))
        switch presentation {
        case .split:
            // This persistent sidebar (iPad/Mac Catalyst) has no drawer to close, but
            // selectConversation is the same expensive call as the iPhone drawer's, so it
            // needs the same "show the loader before binding" sequencing or the loading
            // overlay never appears while a long conversation's messages load.
            chatManager.isSwitchingConversation = true
            Task { @MainActor in
                chatManager.selectConversation(convo)
            }
        case .drawer(let isOpen):
            // Order matters, and needs to be *guaranteed*, not just likely: close the drawer,
            // wait for that animation to genuinely finish, only then show the loading spinner
            // and bind the conversation. selectConversation triggers the expensive part (a
            // long conversation's full List row diff); starting it before the drawer's
            // dismiss has actually rendered bundles that heavy work into the same transaction
            // and blocks the drawer from visibly closing on time. An arbitrary sleep can still
            // lose the race under load — completionCriteria: .logicallyComplete gives a real
            // callback for exactly when this animation finishes.
            withAnimation(.default, completionCriteria: .logicallyComplete) {
                isOpen.wrappedValue = false
            } completion: {
                chatManager.isSwitchingConversation = true
                Task { @MainActor in
                    chatManager.selectConversation(convo)
                }
            }
        }
    }

    // MARK: - 4 Footer

    @ViewBuilder
    private var footer: some View {
        // Upgrade to Pro — individual free users only. Also gated on
        // hasCheckedSubscriptionStatus so an actual Pro user doesn't see this flash briefly
        // while hasActiveSubscription still holds its default false, before the real check
        // (local entitlements + backend sync) completes.
        if authManager.realm == "individual" && iapManager.hasCheckedSubscriptionStatus
            && !iapManager.hasActiveSubscription {
            Button {
                closeDrawer()
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BFColor.primaryTint, in: Capsule())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BFColor.primary)
            .accessibilityIdentifier("upgradeToProButton")
            .bfPointerHover()
        }

        profileMenu
    }

    private var profileMenuRows: [BFDropdownRow] {
        var rows = [BFDropdownRow("Settings", systemImage: "gear") {
            closeDrawer()
            onOpenSettings()
        }]
        if authManager.realm == "individual" {
            rows.append(BFDropdownRow(
                iapManager.hasActiveSubscription ? "Manage Subscription" : "Upgrade to Pro",
                systemImage: iapManager.hasActiveSubscription ? "checkmark.seal" : "sparkles"
            ) {
                closeDrawer()
                onOpenSubscription()
            })
        }
        rows.append(BFDropdownRow("Help & Support", systemImage: "questionmark.circle") {
            closeDrawer()
            onOpenURL(helpURL)
        })
        return rows
    }

    @ViewBuilder
    private var profileMenu: some View {
        switch presentation {
        case .split:
            // BFDropdownMenu, not Menu — this column is used for BOTH iPad and Mac Catalyst
            // (routed by size class, not platform — see AppShell.body's isRegular check), and
            // native Menu turned out to have a second bug beyond missing hover: opening it from
            // inside a NavigationSplitView's sidebar column collapses that sidebar entirely on
            // iPadOS (confirmed via live-device screenshots — bluefunda/cai-ios#292/#293). Not
            // used for ModeModelPicker/PersonaComposerControl or the attach menu, which have
            // their own documented reasons to stay on Menu (cai-ios#257).
            BFDropdownMenu(rows: profileMenuRows) { profileTriggerLabel }
                .accessibilityIdentifier("profileMenuButton")
        case .drawer:
            // Plain native Menu — the iPhone drawer is a ZStack overlay, no
            // NavigationSplitView, so neither the missing-hover nor the
            // sidebar-collapse-on-open issues above apply: hover is meaningless for touch,
            // and there's no split-view sidebar to collapse.
            Menu {
                ForEach(profileMenuRows) { row in
                    Button(role: row.role, action: row.action) {
                        Label(row.title, systemImage: row.systemImage)
                    }
                }
            } label: {
                profileTriggerLabel
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileMenuButton")
        }
    }

    private var profileTriggerLabel: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(BFColor.primary.gradient)
                .frame(width: 30, height: 30)
                .overlay {
                    Text(authManager.currentUser?.name.prefix(1).uppercased() ?? "U")
                        .font(BFFont.sidebarItemMed).foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
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
                HStack(spacing: 6) {
                    if let organization = authManager.currentUser?.organization {
                        OrganizationChip(alias: organization)
                    }
                    if let email = authManager.currentUser?.email {
                        Text(email).font(BFFont.sidebarMeta).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.0001))
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func switchSpace(to space: AppSpace) {
        guard space != workspace.activeSpace else { return }
        // Cross-fade layers 3a/3b (P13); none under Reduce Motion.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: BFMotion.normal)) {
            workspace.activeSpace = space
        }
    }

    /// Closes the iPhone drawer; a no-op for the persistent split-view column.
    private func closeDrawer() {
        guard case .drawer(let isOpen) = presentation else { return }
        withAnimation { isOpen.wrappedValue = false }
    }
}

// MARK: - Presentation Chrome

/// The per-presentation modifiers the two old sidebars each carried.
private struct PresentationChrome: ViewModifier {
    let presentation: SidebarPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .split:
            content
                .toolbar(.hidden, for: .navigationBar)
                #if targetEnvironment(macCatalyst)
                .toolbar(removing: .sidebarToggle)
                #endif
        case .drawer:
            content
                .shadow(color: .black.opacity(0.10), radius: 18, x: 2, y: 0)
        }
    }
}
