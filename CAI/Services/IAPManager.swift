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
                }
            }
        }
    }
}
