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
        guard let bffService else { return }
        do {
            let subscription = try await bffService.fetchSubscription()
            if subscription.isPro {
                hasActiveSubscription = true
            }
        } catch {
            print("[IAPManager] Backend subscription sync failed: \(error)")
        }
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
