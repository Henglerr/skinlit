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

@MainActor
public final class StoreKitBillingService: BillingService {
    private let productIDs: [String]

    public init(productIDs: [String]) {
        self.productIDs = productIDs
    }

    public func fetchPackages() async throws -> [PaywallPackage] {
        let products = try await Product.products(for: productIDs)
        guard !products.isEmpty else {
            throw BillingError.productsUnavailable
        }

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
        let products = try await Product.products(for: [id])
        guard let product = products.first else {
            throw BillingError.productNotFound
        }
        return product
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
}

#if DEBUG
public final class MockBillingService: BillingService {
    public init() {}

    public func fetchPackages() async throws -> [PaywallPackage] {
        [
            PaywallPackage(
                id: "com.skinscore.pro.weekly",
                title: "Weekly",
                priceText: "$2.99",
                trialDescription: nil,
                badge: nil
            ),
            PaywallPackage(
                id: "com.skinscore.pro.monthly",
                title: "Monthly",
                priceText: "$6.99",
                trialDescription: "3-day free trial",
                badge: "MOST POPULAR"
            ),
            PaywallPackage(
                id: "com.skinscore.pro.yearly",
                title: "Yearly",
                priceText: "$29.99",
                trialDescription: "3-day free trial",
                badge: "BEST VALUE"
            )
        ]
    }

    public func purchase(_ packageId: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 300_000_000)
        return true
    }

    public func restore() async throws -> Bool {
        true
    }

    public func currentEntitlement() async throws -> SubscriptionEntitlement {
        SubscriptionEntitlement(isActive: false, productId: nil, expirationDate: nil)
    }
}
#endif
