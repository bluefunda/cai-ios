import StoreKit

@MainActor
final class IAPManager: ObservableObject {
    static let productIDs: Set<String> = [
        "com.bluefunda.ai.pro.monthly",
        "com.bluefunda.ai.pro.yearly"
    ]

    @Published var products: [Product] = []
    @Published var hasActiveSubscription = false
    @Published var isPurchasing = false
    @Published var purchaseError: String?
    @Published var isLoadingProducts = false
    /// False until checkSubscriptionStatus()'s full check (local entitlements + backend sync)
    /// has completed at least once. hasActiveSubscription defaults to false, so gating "Upgrade
    /// to Pro" on it alone showed that button to an actual Pro user for the brief window between
    /// launch and this check completing, before flipping to the correct Pro state — this lets
    /// callers hide the upgrade prompt entirely until the real status is known instead.
    @Published var hasCheckedSubscriptionStatus = false

    /// Injected after init so IAPManager can register purchases with the backend.
    var bffService: BFFAPIService?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await checkSubscriptionStatus()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // yearly first (recommended/best-value slot), monthly second
            products = loaded.sorted { $0.id.contains("yearly") && !$1.id.contains("yearly") }
        } catch {
            print("[IAPManager] Failed to load products: \(error)")
        }
    }

    func checkSubscriptionStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productType == .autoRenewable,
                  Self.productIDs.contains(tx.productID),
                  tx.revocationDate == nil else { continue }
            active = true
            break
        }
        hasActiveSubscription = active
        // Also sync with backend to catch Stripe subscribers who have no Apple transactions
        await syncWithBackend()
    }

    func syncWithBackend() async {
        // bffService is injected later, once auth completes (see CAIApp.swift) — this first
        // runs from init(), before that injection, so it's still nil here. Deliberately leaves
        // hasCheckedSubscriptionStatus false in that case rather than setting it regardless: a
        // Stripe/web-only Pro subscriber has no local StoreKit entitlement, so without a real
        // backend attempt "checked" would be a lie, and the UI would show "Upgrade to Pro" to an
        // actual Pro user for the whole window until CAIApp's own post-auth syncWithBackend call
        // corrects it — which is the flash this flag exists to prevent.
        guard let bffService else { return }
        do {
            let subscription = try await bffService.fetchSubscription()
            hasActiveSubscription = subscription.isPro
        } catch {
            print("[IAPManager] Backend subscription sync failed: \(error)")
        }
        hasCheckedSubscriptionStatus = true
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = "Purchase could not be verified. Please try again."
                    return
                }
                await tx.finish()
                hasActiveSubscription = true
                let txID = String(tx.originalID)
                Task { try? await self.bffService?.registerAppleSubscription(originalTransactionId: txID) }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result,
                   Self.productIDs.contains(tx.productID) {
                    await tx.finish()
                    await self.checkSubscriptionStatus()
                    let txID = String(tx.originalID)
                    Task { try? await self.bffService?.registerAppleSubscription(originalTransactionId: txID) }
                }
            }
        }
    }
}
