import SwiftUI

struct RateLimitView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @State private var isRefreshing = false

    private var isUnlimited: Bool {
        authManager.realm == "trm" || (chatManager.rateLimit?.dailyLimit == 0)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let info = chatManager.rateLimit {
                    if isUnlimited {
                        unlimitedContent
                    } else {
                        rateContent(info: info)
                    }
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
                await chatManager.loadRateLimit()
            }
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

            // Daily Usage
            if info.dailyLimit > 0 {
                Section {
                    UsageRow(
                        label: "Daily Tokens",
                        used: info.dailyUsed,
                        limit: info.dailyLimit,
                        percent: info.dailyPercent
                    )
                } header: {
                    Text("Daily Usage")
                }
            }

            // Monthly Usage
            if info.monthlyLimit > 0 {
                Section {
                    UsageRow(
                        label: "Monthly Tokens",
                        used: info.monthlyUsed,
                        limit: info.monthlyLimit,
                        percent: info.monthlyPercent
                    )
                } header: {
                    Text("Monthly Usage")
                }
            }
        }
    }

    private func refresh() {
        isRefreshing = true
        Task {
            await chatManager.loadRateLimit()
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
}

// MARK: - Usage Row

struct UsageRow: View {
    let label: String
    let used: Int
    let limit: Int
    let percent: Double

    private var progressColor: Color {
        if percent > 0.9 { return .red }
        if percent > 0.7 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(used.formatted()) / \(limit.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: percent)
                .tint(progressColor)
                .animation(.easeInOut, value: percent)

            HStack {
                Text("\(Int(percent * 100))% used")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\((limit - used).formatted()) remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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

#Preview {
    RateLimitView()
        .environmentObject({
            let m = ChatManager(service: BFFChatService())
            m.rateLimit = RateLimitInfo(
                planName: "premium",
                dailyUsed: 7_500,
                dailyLimit: 10_000,
                monthlyUsed: 45_000,
                monthlyLimit: 100_000,
                isBlocked: false,
                blockReason: nil,
                resetLabel: "1h"
            )
            return m
        }())
        .environmentObject(AuthManager())
}
