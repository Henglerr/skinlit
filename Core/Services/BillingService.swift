import Foundation

public struct PaywallPackage: Identifiable {
    public let id: String
    public let title: String
    public let priceText: String
    public let trialDays: Int?
    public let badge: String?
    
    public init(id: String, title: String, priceText: String, trialDays: Int? = nil, badge: String? = nil) {
        self.id = id
        self.title = title
        self.priceText = priceText
        self.trialDays = trialDays
        self.badge = badge
    }
}

public protocol BillingService {
    func fetchPackages() async throws -> [PaywallPackage]
    func purchase(_ packageId: String) async throws -> Bool
    func restore() async throws -> Bool
}

// Mock implementation for MVP Development
public class MockBillingService: BillingService {
    public init() {}
    
    public func fetchPackages() async throws -> [PaywallPackage] {
        return [
            PaywallPackage(id: "weekly", title: "Weekly", priceText: "$2.99 / week"),
            PaywallPackage(id: "monthly", title: "Monthly", priceText: "$6.99 / month", trialDays: 3, badge: "MOST POPULAR"),
            PaywallPackage(id: "yearly", title: "Yearly", priceText: "$29.99 / year", trialDays: 3, badge: "BEST VALUE")
        ]
    }
    
    public func purchase(_ packageId: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return true
    }
    
    public func restore() async throws -> Bool {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return true
    }
}
