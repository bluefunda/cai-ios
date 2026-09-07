import SwiftUI

struct RateLimitView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var isRefreshing = false
    @State private var lastFetchedAt = Date()

    // Driven only by the resolved plan's actual weekly limit — not by realm. A TRM-realm
    // account with a real pro/free plan should see its real usage like anyone else;
    // "Unlimited" is reserved for a plan actually configured with no weekly cap.
    private var isUnlimited: Bool {
        chatManager.rateLimit?.weeklyLimit == 0
    }

    // No own NavigationStack — this is embedded directly as SettingsView's Usage detail
    // pane (which already provides one), matching cai-android's flat Settings -> Usage
    // navigation instead of pushing through an extra intermediate summary screen.
    var body: some View {
        Group {
            if let info = chatManager.rateLimit {
                if isUnlimited {
                    unlimitedContent
                } else {
                    rateContent(info: info)
                }
            } else if let rateLimitError = chatManager.rateLimitError {
                ErrorRateLimitView(message: rateLimitError)
            } else {
                LoadingRateLimitView()
            }
        }
        .navigationTitle("Usage & Limits")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task {
            isRefreshing = true
            await chatManager.loadRateLimit()
            lastFetchedAt = Date()
            isRefreshing = false
        }
    }

    private var unlimitedContent: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlimited Access")
                            .font(.headline)
                        Text("No token limits apply to your account.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Status")
            }
        }
    }

    @ViewBuilder
    private func rateContent(info: RateLimitInfo) -> some View {
        List {
            // Plan Badge
            Section {
                HStack {
                    Label("Account", systemImage: "person.circle")
                    Spacer()
                    Text(info.planName.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if info.isBlocked {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundColor(.red)
                        Text(info.blockReason ?? "Account is blocked")
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Plan")
            }

            // Hourly Usage (5-hour rolling session window)
            if info.hourlyLimit > 0 {
                Section {
                    UsageRow(resetLabel: Self.resetPhrase(info.hourlyResetLabel), percent: info.hourlyPercent)
                } header: {
                    Text("Current Session")
                }
            }

            // Weekly Usage
            if info.weeklyLimit > 0 {
                Section {
                    UsageRow(resetLabel: Self.resetPhrase(info.resetLabel), percent: info.weeklyPercent)
                } header: {
                    Text("Weekly Limits")
                }
            }

            Section {
                LastUpdatedRow(lastFetchedAt: lastFetchedAt)
            }
        }
    }

    private func refresh() {
        isRefreshing = true
        Task {
            await chatManager.loadRateLimit()
            lastFetchedAt = Date()
            isRefreshing = false
        }
    }

    private func planColor(_ plan: String) -> Color {
        switch plan.lowercased() {
        case "enterprise": return .purple
        case "premium": return .blue
        case "trial": return .orange
        default: return .gray
        }
    }

    // "shortly" is an adverb, not a duration — "Resets in shortly" reads as broken
    // grammar. It shows up whenever the window's own reset timestamp has already
    // elapsed but no new request has come in yet to roll it forward, so the honest
    // phrasing is that the window resets immediately on next use, not "in" some
    // duration.
    static func resetPhrase(_ label: String) -> String {
        label == "shortly" ? "Resets shortly" : "Resets in \(label)"
    }
}

// MARK: - Usage Row

// No raw token counts or "remaining" figures — just the reset countdown, the bar
// itself, and a percentage, matching how Claude's own usage-limits UI presents this:
// the exact numbers aren't meaningful to end users, only how close they are to the
// limit and when it clears.
struct UsageRow: View {
    let resetLabel: String
    let percent: Double

    private var progressColor: Color {
        if percent > 0.9 { return .red }
        if percent > 0.7 { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            // layoutPriority + lineLimit keep two-part durations ("4h 45m", "6d 23h")
            // on one line instead of wrapping and desyncing this row's height against
            // its sibling row.
            Text(resetLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .layoutPriority(1)

            ProgressView(value: percent)
                .tint(progressColor)
                .animation(.easeInOut, value: percent)

            Text("\(Int(percent * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Last Updated Row

struct LastUpdatedRow: View {
    let lastFetchedAt: Date

    // Ticks every 30s so this stays honest while the user sits on the screen,
    // instead of freezing at "just now" forever once the fetch completes.
    var body: some View {
        TimelineView(.periodic(from: lastFetchedAt, by: 30)) { context in
            Text("Last updated: \(label(now: context.date))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func label(now: Date) -> String {
        let elapsedMinutes = Int(now.timeIntervalSince(lastFetchedAt) / 60)
        switch elapsedMinutes {
        case ..<1: return "just now"
        case ..<60: return "\(elapsedMinutes)m ago"
        default: return "\(elapsedMinutes / 60)h ago"
        }
    }
}

// MARK: - Loading State

struct LoadingRateLimitView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Loading usage data…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State

struct ErrorRateLimitView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(BFColor.error)
            Text("Couldn't load usage data")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack { RateLimitView() }
        .environmentObject({
            let m = ChatManager(service: BFFChatService())
            m.rateLimit = RateLimitInfo(
                planName: "pro",
                hourlyUsed: 7_500,
                hourlyLimit: 10_000,
                weeklyUsed: 45_000,
                weeklyLimit: 100_000,
                isBlocked: false,
                blockReason: nil,
                resetLabel: "1h",
                hourlyResetLabel: "3h 20m"
            )
            return m
        }())
}
