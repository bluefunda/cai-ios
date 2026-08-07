import SwiftUI

// MARK: - Preview-only — kept out of ChatView.swift to stay under SwiftLint's
// file_length limit (bluefunda/cai-ios#217 UI polish previews).

#Preview("Rate Limit Banner — Warning") {
    RateLimitBanner(status: .warning, percent: 0.85, resetLabel: "6h")
}

#Preview("Rate Limit Banner — Exceeded") {
    RateLimitBanner(status: .exceeded, percent: 1.0, resetLabel: "midnight")
}

#Preview("Rate Limit Banner — Blocked") {
    RateLimitBanner(status: .blocked, percent: 1.0, resetLabel: "midnight")
}

#Preview("Rate Limit Modal") {
    ZStack {
        Color.black.opacity(0.4).ignoresSafeArea()
        RateLimitModal(
            info: RateLimitInfo(
                planName: "premium", dailyUsed: 10_000, dailyLimit: 10_000,
                monthlyUsed: 45_000, monthlyLimit: 100_000,
                isBlocked: false, blockReason: nil, resetLabel: "6h"
            ),
            period: "daily",
            resetLabel: "6h",
            onClose: {},
            onUpgrade: {}
        )
    }
}
