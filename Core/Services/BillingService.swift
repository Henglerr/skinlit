import Foundation
import StoreKit

public struct PaywallPackage: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let priceText: String
    public let trialDescription: String?
    public let badge: String?

    public init(
        id: String,
        title: String,
        priceText: String,
        trialDescription: String? = nil,
        badge: String? = nil
    ) {
        self.id = id
        self.title = title
        self.priceText = priceText
        self.trialDescription = trialDescription
        self.badge = badge
    }
}

public struct SubscriptionEntitlement: Equatable {
    public let isActive: Bool
    public let productId: String?
    public let expirationDate: Date?

    public init(isActive: Bool, productId: String?, expirationDate: Date?) {
        self.isActive = isActive
        self.productId = productId
        self.expirationDate = expirationDate
    }
}

public enum BillingError: LocalizedError {
    case productsUnavailable
    case productNotFound
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            return "Could not load subscription options right now."
        case .productNotFound:
            return "The selected subscription is not available."
        case .verificationFailed:
            return "Purchase verification failed."
        }
    }
}

public protocol BillingService {
    func fetchPackages() async throws -> [PaywallPackage]
    func purchase(_ packageId: String) async throws -> Bool
    func restore() async throws -> Bool
    func currentEntitlement() async throws -> SubscriptionEntitlement
}

#if DEBUG
private func debugBillingPackages(for productIDs: [String]) -> [PaywallPackage] {
    productIDs.compactMap { productID in
        switch productID {
        case "com.skinlit.pro.weekly":
            return PaywallPackage(
                id: productID,
                title: "Weekly",
                priceText: "$4.99",
                trialDescription: "7-day free trial",
                badge: nil
            )
        case "com.skinlit.pro.monthly":
            return PaywallPackage(
                id: productID,
                title: "Monthly",
                priceText: "$14.99",
                trialDescription: "7-day free trial",
                badge: "MOST POPULAR"
            )
        case "com.skinlit.pro.yearly":
            return PaywallPackage(
                id: productID,
                title: "Yearly",
                priceText: "$49.99",
                trialDescription: "7-day free trial",
                badge: "BEST VALUE"
            )
        default:
            return nil
        }
    }
}

@MainActor
public final class DeveloperFallbackBillingService: BillingService {
    private let primary: BillingService
    private let fallback: BillingService
    private var usesFallbackCatalog = false

    public init(primary: BillingService, fallback: BillingService) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchPackages() async throws -> [PaywallPackage] {
        do {
            let packages = try await primary.fetchPackages()
            guard !packages.isEmpty else {
                usesFallbackCatalog = true
                return try await fallback.fetchPackages()
            }

            usesFallbackCatalog = false
            return packages
        } catch {
            usesFallbackCatalog = true
            return try await fallback.fetchPackages()
        }
    }

    public func purchase(_ packageId: String) async throws -> Bool {
        if usesFallbackCatalog {
            return try await fallback.purchase(packageId)
        }
        return try await primary.purchase(packageId)
    }

    public func restore() async throws -> Bool {
        if usesFallbackCatalog {
            return try await fallback.restore()
        }

        do {
            return try await primary.restore()
        } catch {
            return try await fallback.restore()
        }
    }

    public func currentEntitlement() async throws -> SubscriptionEntitlement {
        if usesFallbackCatalog {
            return try await fallback.currentEntitlement()
        }

        do {
            return try await primary.currentEntitlement()
        } catch {
            return try await fallback.currentEntitlement()
        }
    }
}
#endif

@MainActor
public final class StoreKitBillingService: BillingService {
    private let productIDs: [String]
    private var cachedProductsByID: [String: Product] = [:]

    public init(productIDs: [String]) {
        self.productIDs = productIDs
    }

    public func fetchPackages() async throws -> [PaywallPackage] {
        let products: [Product]
        do {
            products = try await Product.products(for: productIDs)
        } catch {
#if DEBUG
            if allowsDebugFallbackPackages {
                return debugFallbackPackages()
            }
#else
            throw BillingError.productsUnavailable
#endif
#if DEBUG
            throw BillingError.productsUnavailable
#endif
        }

        guard !products.isEmpty else {
#if DEBUG
            if allowsDebugFallbackPackages {
                return debugFallbackPackages()
            }
#else
            throw BillingError.productsUnavailable
#endif
#if DEBUG
            throw BillingError.productsUnavailable
#endif
        }

        cachedProductsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        let orderLookup = Dictionary(uniqueKeysWithValues: productIDs.enumerated().map { ($0.element, $0.offset) })
        let sorted = products.sorted { lhs, rhs in
            (orderLookup[lhs.id] ?? Int.max) < (orderLookup[rhs.id] ?? Int.max)
        }

        return sorted.map { product in
            PaywallPackage(
                id: product.id,
                title: title(for: product),
                priceText: product.displayPrice,
                trialDescription: trialDescription(for: product),
                badge: badge(for: product.id)
            )
        }
    }

    public func purchase(_ packageId: String) async throws -> Bool {
        let product = try await findProduct(by: packageId)
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    public func restore() async throws -> Bool {
        try await AppStore.sync()
        let entitlement = try await currentEntitlement()
        return entitlement.isActive
    }

    public func currentEntitlement() async throws -> SubscriptionEntitlement {
        let now = Date()
        var bestTransaction: Transaction?

        for await result in Transaction.currentEntitlements {
            let transaction = try verifiedTransaction(from: result)
            guard productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= now { continue }

            if let currentBest = bestTransaction {
                let bestDate = currentBest.expirationDate ?? .distantFuture
                let candidateDate = transaction.expirationDate ?? .distantFuture
                if candidateDate > bestDate {
                    bestTransaction = transaction
                }
            } else {
                bestTransaction = transaction
            }
        }

        guard let bestTransaction else {
            return SubscriptionEntitlement(isActive: false, productId: nil, expirationDate: nil)
        }

        return SubscriptionEntitlement(
            isActive: true,
            productId: bestTransaction.productID,
            expirationDate: bestTransaction.expirationDate
        )
    }

    private func findProduct(by id: String) async throws -> Product {
        if let cached = cachedProductsByID[id] {
            return cached
        }

        let products = try await Product.products(for: [id])
        guard let product = products.first else {
            throw BillingError.productNotFound
        }
        cachedProductsByID[id] = product
        return product
    }

    private var allowsDebugFallbackPackages: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#else
        false
#endif
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw BillingError.verificationFailed
        }
    }

    private func badge(for productID: String) -> String? {
        let lower = productID.lowercased()
        if lower.contains("year") || lower.contains("annual") {
            return "BEST VALUE"
        }
        if lower.contains("month") {
            return "MOST POPULAR"
        }
        return nil
    }

    private func title(for product: Product) -> String {
        let lower = product.id.lowercased()
        if lower.contains("week") { return "Weekly" }
        if lower.contains("month") { return "Monthly" }
        if lower.contains("year") || lower.contains("annual") { return "Yearly" }
        return product.displayName
    }

    private func trialDescription(for product: Product) -> String? {
        guard
            let subscription = product.subscription,
            let intro = subscription.introductoryOffer,
            intro.paymentMode == .freeTrial
        else {
            return nil
        }

        return "\(periodDescription(intro.period)) free trial"
    }

    private func periodDescription(_ period: Product.SubscriptionPeriod) -> String {
        let unitText: String
        switch period.unit {
        case .day: unitText = period.value == 1 ? "day" : "days"
        case .week: unitText = period.value == 1 ? "week" : "weeks"
        case .month: unitText = period.value == 1 ? "month" : "months"
        case .year: unitText = period.value == 1 ? "year" : "years"
        @unknown default: unitText = "days"
        }
        return "\(period.value)-\(unitText)"
    }

#if DEBUG
    private func debugFallbackPackages() -> [PaywallPackage] {
        debugBillingPackages(for: productIDs)
    }
#endif
}

#if DEBUG
@MainActor
public final class MockBillingService: BillingService {
    private let packages: [PaywallPackage]
    private var activeProductId: String?

    public init(productIDs: [String]? = nil) {
        self.packages = debugBillingPackages(for: productIDs ?? AppConfig.subscriptionProductIds)
    }

    public func fetchPackages() async throws -> [PaywallPackage] {
        packages
    }

    public func purchase(_ packageId: String) async throws -> Bool {
        guard packages.contains(where: { $0.id == packageId }) else {
            throw BillingError.productNotFound
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        activeProductId = packageId
        return true
    }

    public func restore() async throws -> Bool {
        activeProductId != nil
    }

    public func currentEntitlement() async throws -> SubscriptionEntitlement {
        SubscriptionEntitlement(
            isActive: activeProductId != nil,
            productId: activeProductId,
            expirationDate: nil
        )
    }
}
#endif
