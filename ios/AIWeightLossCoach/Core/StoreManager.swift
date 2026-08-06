import Foundation
import Observation
import StoreKit
 
@MainActor
@Observable
final class StoreManager {
    var products: [Product] = []
    var isPremium = false
    var expiresAt: Date?
    var purchaseError: String?
    var isPurchasing = false
    var isLoadingProducts = false
 
    /// Holds the transaction-listener task.
    ///
    /// `deinit` is nonisolated and cannot read main-actor state under Swift 6
    /// strict concurrency, so the task lives in this small reference box rather
    /// than in a stored property on the actor-isolated class.
    private let updates = TaskBox()
 
    var monthly: Product? { products.first { $0.id == AppConfig.monthlyProductID } }
    var annual: Product? { products.first { $0.id == AppConfig.annualProductID } }
 
    /// Percent saved by paying annually, rounded down. Nil when both prices aren't loaded.
    var annualSavingPercent: Int? {
        guard let monthly, let annual else { return nil }
        let yearAtMonthly = monthly.price * 12
        guard yearAtMonthly > 0 else { return nil }
        let saving = (yearAtMonthly - annual.price) / yearAtMonthly * 100
        return Int(truncating: saving as NSDecimalNumber)
    }
 
    func start() {
        updates.cancel()
        updates.task = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await self.submit(transaction)
                    await transaction.finish()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }
 
    deinit { updates.cancel() }
 
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: AppConfig.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Couldn't load subscription options. Check your connection."
        }
    }
 
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
 
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await submit(transaction)
                    await transaction.finish()
                    return true
                case .unverified:
                    purchaseError = "That purchase couldn't be verified with the App Store."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "The purchase is waiting on approval. We'll unlock Premium as soon as it clears."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }
 
    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPremium {
                purchaseError = "No active subscription found on this Apple Account."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }
 
    func refreshEntitlements() async {
        var active = false
        var latestExpiry: Date?
 
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  AppConfig.productIDs.contains(transaction.productID) else { continue }
            if let expiry = transaction.expirationDate, expiry > Date() {
                active = true
                latestExpiry = max(latestExpiry ?? expiry, expiry)
                await submit(transaction)
            }
        }
 
        isPremium = active
        expiresAt = latestExpiry
 
        // The server is the source of truth for gating; reconcile with it.
        if let status: SubscriptionStatus = try? await APIClient.shared.get("subscriptions/status") {
            isPremium = status.isPremium
            expiresAt = status.expiresAt
        }
    }
 
    private func submit(_ transaction: Transaction) async {
        let payload = VerifyPurchaseRequest(
            signedTransaction: nil,
            productId: transaction.productID,
            originalTransactionId: String(transaction.originalID),
            transactionId: String(transaction.id),
            purchaseDateMs: Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
            expiresDateMs: transaction.expirationDate.map { Int($0.timeIntervalSince1970 * 1000) },
            environment: transaction.environment == .production ? "Production" : "Sandbox"
        )
        do {
            let status: SubscriptionStatus = try await APIClient.shared.post("subscriptions/verify", body: payload)
            isPremium = status.isPremium
            expiresAt = status.expiresAt
        } catch {
            // Keep local entitlement so a network blip doesn't lock a paying customer out.
            isPremium = transaction.expirationDate.map { $0 > Date() } ?? isPremium
        }
    }
}
 
/// Thread-safe, non-isolated holder for a cancellable task.
///
/// Exists so `StoreManager.deinit` can cancel the StoreKit listener without
/// touching main-actor-isolated storage.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?
 
    var task: Task<Void, Never>? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _task
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _task = newValue
        }
    }
 
    func cancel() {
        lock.lock()
        let existing = _task
        _task = nil
        lock.unlock()
        existing?.cancel()
    }
}
