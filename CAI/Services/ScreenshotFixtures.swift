#if DEBUG
import Foundation
import SwiftData

/// Seeds a fake authenticated session + demo conversations for App Store
/// screenshot automation (fastlane `snapshot`, driven by CAIUITests). Entirely
/// local — no Keycloak/BFF network calls — so it only ever compiles into
/// Debug builds (`build_app`/archives use Release) and only activates behind
/// an explicit launch argument, never in a shipped build.
///
/// Campaigns map onto real product features so each Custom Product Page can
/// showcase one: "chat" (general assistant) or "code" (ABAP/SAP-focused chat).
enum ScreenshotFixtures {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestScreenshots")
    }

    static var campaign: String {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UITestCampaign"), idx + 1 < args.count else {
            return "chat"
        }
        return args[idx + 1]
    }

    private static let demoUser = User(
        id: "screenshot-user",
        email: "alex.morgan@example.com",
        name: "Alex Morgan",
        roles: []
    )

    /// Called once from CAIApp's `.task` instead of the real auth-restore +
    /// storage-configure + BFF-connect sequence.
    @MainActor
    static func bootstrap(
        authManager: AuthManager,
        chatManager: ChatManager,
        iapManager: IAPManager,
        context: ModelContext
    ) {
        authManager.seedForScreenshots(user: demoUser, accessToken: "screenshot-token")
        seedConversations(in: context)
        chatManager.configureStorage(context)
        // No real BFF connection is ever made in fixture mode, so drive the
        // connection/subscription state directly rather than leaving the
        // ConnectionBanner showing "Disconnected" over every screenshot.
        chatManager.connectionStatus = .connected
        // Always false so the "Upgrade to Pro" banner — the test suite's route
        // to the Subscription screenshot — is guaranteed present.
        iapManager.hasActiveSubscription = false
    }

    private static func seedConversations(in context: ModelContext) {
        // A simulator reused across campaigns/runs keeps its SwiftData store
        // on disk — wipe any prior fixture data first so this launch always
        // reflects the current campaign, never a leftover one.
        let existing = (try? context.fetch(FetchDescriptor<PersistedConversation>())) ?? []
        for conversation in existing { context.delete(conversation) }

        for demo in demoConversations(for: campaign) {
            let conversation = PersistedConversation(
                id: demo.id, title: demo.title, model: demo.model, createdAt: demo.createdAt
            )
            context.insert(conversation)
            for (offset, message) in demo.messages.enumerated() {
                let persisted = PersistedMessage(
                    id: "\(demo.id)-\(offset)",
                    conversationId: demo.id,
                    roleRaw: message.role.rawValue,
                    content: message.content,
                    timestamp: demo.createdAt.addingTimeInterval(TimeInterval(offset * 20))
                )
                persisted.conversation = conversation
                context.insert(persisted)
            }
        }
        try? context.save()
    }

    // MARK: - Demo content

    private struct DemoConversation {
        let id: String
        let title: String
        let model: String
        let createdAt: Date
        let messages: [(role: MessageRole, content: String)]
    }

    private static func demoConversations(for campaign: String) -> [DemoConversation] {
        let now = Date()
        switch campaign {
        case "code":
            return [
                DemoConversation(
                    id: "screenshot-code-1",
                    title: "ABAP Code Review",
                    model: "claude-sonnet-5",
                    createdAt: now,
                    messages: [
                        (.user, "Can you review this ABAP method for the sales order total and suggest a fix? It's returning zero for orders with multiple currencies."),
                        (.assistant, """
                        The issue is the running total isn't converted to a common currency before summing. Here's the fix:

                        ```abap
                        METHOD calculate_total.
                          DATA(lv_total) = 0.
                          LOOP AT it_items INTO DATA(ls_item).
                            lv_total += convert_currency(
                              iv_amount   = ls_item-amount
                              iv_from_cur = ls_item-currency
                              iv_to_cur   = iv_target_currency ).
                          ENDLOOP.
                          rv_total = lv_total.
                        ENDMETHOD.
                        ```

                        This converts each line item into the order's target currency before accumulating, so mixed-currency orders total correctly.
                        """)
                    ]
                )
            ]
        default: // "chat"
            return [
                DemoConversation(
                    id: "screenshot-chat-1",
                    title: "Q3 Revenue Analysis",
                    model: "claude-sonnet-5",
                    createdAt: now,
                    messages: [
                        (.user, "Summarize the Q3 revenue trend across our top 3 regions and flag anything unusual."),
                        (.assistant, """
                        Here's the Q3 breakdown:

                        - **North America** — up 12% QoQ, driven mainly by renewals
                        - **EMEA** — flat, in line with seasonal expectations
                        - **APAC** — up 34% QoQ — worth flagging: this is well above trend and concentrated in a single account, so it may not repeat next quarter

                        Overall revenue is healthy, but I'd treat the APAC number as one-time rather than a new baseline when forecasting Q4.
                        """)
                    ]
                )
            ]
        }
    }
}
#endif
