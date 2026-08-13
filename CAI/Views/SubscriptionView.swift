import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var iapManager: IAPManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedProductID: String = "com.bluefunda.ai.pro.yearly"

    private var selectedProduct: Product? {
        iapManager.products.first { $0.id == selectedProductID }
    }
    private var yearlyProduct: Product? { iapManager.products.first { $0.id.contains("yearly") } }
    private var monthlyProduct: Product? { iapManager.products.first { $0.id.contains("monthly") } }

    private let privacyURL = URL(string: "https://bluefunda.com/privacy/")!
    private let termsURL   = URL(string: "https://bluefunda.com/terms/")!

    var body: some View {
        NavigationStack {
            Group {
                if iapManager.hasActiveSubscription {
                    subscribedView
                } else {
                    upgradeView
                }
            }
            .navigationTitle(iapManager.hasActiveSubscription ? "Your Plan" : "Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if iapManager.products.isEmpty {
                await iapManager.loadProducts()
            }
        }
    }

    // MARK: - Already subscribed

    private var subscribedView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(BFColor.primary.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(BFColor.primary)
                }

                VStack(spacing: 6) {
                    Text("You're on Pro")
                        .font(BFFont.h3)
                    Text("This includes:")
                        .font(BFFont.body)
                        .foregroundStyle(BFColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FeatureBullet(icon: "checkmark.circle", text: "Everything in Free")
                    FeatureBullet(icon: "sparkles", text: "Extended access to models from OpenAI, Llama, DeepSeek")
                    FeatureBullet(icon: "infinity", text: "Extended limits on general chat, file uploads and data analysis")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            Spacer()

            Button {
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            } label: {
                Label("Manage Subscription", systemImage: "arrow.up.right")
                    .font(BFFont.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Upgrade flow

    private var upgradeView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(BFColor.primary.gradient)
                            .frame(width: 72, height: 72)
                            .bfShadow(BFShadow.md)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundStyle(BFColor.textInverse)
                    }
                    Text("BlueFunda AI Pro")
                        .font(BFFont.h4)
                    Text("Full access to all features")
                        .font(BFFont.bodySmall)
                        .foregroundStyle(BFColor.textTertiary)
                }
                .padding(.top, 28)
                .padding(.bottom, 24)

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    FeatureBullet(icon: "bubble.left.and.bubble.right", text: "AI-powered chat with leading models")
                    FeatureBullet(icon: "chevron.left.forwardslash.chevron.right", text: "ABAP code assistant & object browser")
                    FeatureBullet(icon: "sparkles", text: "Multiple AI assistants & MCP servers")
                    FeatureBullet(icon: "lock.shield", text: "Secure, private conversations")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Plan cards
                if iapManager.isLoadingProducts {
                    ProgressView().frame(height: 130)
                } else if iapManager.products.isEmpty {
                    Text("Unable to load plans. Check your connection and try again.")
                        .font(BFFont.bodySmall)
                        .foregroundStyle(BFColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .frame(height: 130)
                } else {
                    VStack(spacing: 10) {
                        if let yearly = yearlyProduct {
                            PlanCard(product: yearly, badge: savingsBadge,
                                     isSelected: selectedProductID == yearly.id) {
                                selectedProductID = yearly.id
                            }
                        }
                        if let monthly = monthlyProduct {
                            PlanCard(product: monthly, badge: nil,
                                     isSelected: selectedProductID == monthly.id) {
                                selectedProductID = monthly.id
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Error
                if let err = iapManager.purchaseError {
                    Text(err)
                        .font(BFFont.bodySmall)
                        .foregroundStyle(BFColor.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                }

                // CTA
                Button {
                    guard let product = selectedProduct else { return }
                    Task { await iapManager.purchase(product) }
                } label: {
                    Group {
                        if iapManager.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text(ctaLabel)
                                .font(BFFont.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BFColor.primary, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(iapManager.isPurchasing || selectedProduct == nil)
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Footer
                VStack(spacing: 10) {
                    Button("Restore Purchases") {
                        Task { await iapManager.restorePurchases() }
                    }
                    .font(BFFont.bodySmall)
                    .foregroundStyle(BFColor.primary)
                    .disabled(iapManager.isPurchasing)

                    Text("Subscriptions auto-renew until cancelled. Manage in Settings.")
                        .font(BFFont.micro)
                        .foregroundStyle(BFColor.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 16) {
                        Button("Privacy Policy") { openURL(privacyURL) }
                        Text("·").foregroundStyle(BFColor.textMuted)
                        Button("Terms of Service") { openURL(termsURL) }
                    }
                    .font(BFFont.micro)
                    .foregroundStyle(BFColor.textMuted)
                }
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
        }
    }

    private var ctaLabel: String {
        guard let product = selectedProduct else { return "Subscribe" }
        return "Subscribe · \(product.displayPrice)"
    }

    private var savingsBadge: String? {
        guard let monthly = monthlyProduct, let yearly = yearlyProduct else { return "Best Value" }
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return "Best Value" }
        let saving = (monthlyAnnual - yearly.price) / monthlyAnnual * 100
        let rounded = Int((saving as NSDecimalNumber).doubleValue.rounded())
        return rounded > 0 ? "Save \(rounded)%" : "Best Value"
    }
}

// MARK: - Shared subviews

struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(BFColor.primary)
                .frame(width: 22)
            Text(text)
                .font(BFFont.body)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

private struct PlanCard: View {
    let product: Product
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    private var period: String {
        product.id.contains("yearly") ? "/ year" : product.id.contains("monthly") ? "/ month" : ""
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(BFFont.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(BFFont.micro.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BFColor.primary, in: Capsule())
                        }
                    }
                    Text(product.description)
                        .font(BFFont.bodySmall)
                        .foregroundStyle(BFColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(BFFont.body.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(period)
                        .font(BFFont.micro)
                        .foregroundStyle(BFColor.textTertiary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: BFRadius.md)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0.04),
                            radius: isSelected ? 8 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BFRadius.md)
                    .stroke(isSelected ? BFColor.primary : Color(.systemGray5),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    SubscriptionView()
        .environmentObject(IAPManager())
}
