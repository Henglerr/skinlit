import Foundation
import SwiftData

public struct CachedReferralState: Equatable {
    public let shareCount: Int
    public let validatedReferralCount: Int
    public let rewardCount: Int
    public let claimedCode: String?
    public let inviteCode: String?
    public let inviteURLString: String?
    public let pendingCode: String?

    public init(
        shareCount: Int,
        validatedReferralCount: Int,
        rewardCount: Int,
        claimedCode: String?,
        inviteCode: String?,
        inviteURLString: String?,
        pendingCode: String?
    ) {
        self.shareCount = shareCount
        self.validatedReferralCount = validatedReferralCount
        self.rewardCount = rewardCount
        self.claimedCode = claimedCode
        self.inviteCode = inviteCode
        self.inviteURLString = inviteURLString
        self.pendingCode = pendingCode
    }
}

@MainActor
public final class SettingsRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func settings() throws -> AppLocalSettings {
        let descriptor = FetchDescriptor<AppLocalSettings>()
        let existingSettings = try context.fetch(descriptor)

        if let primary = existingSettings.first {
            var requiresSave = false

            if primary.id != AppLocalSettings.singletonId {
                primary.id = AppLocalSettings.singletonId
                requiresSave = true
            }

            for duplicate in existingSettings.dropFirst() {
                context.delete(duplicate)
                requiresSave = true
            }

            if requiresSave {
                try context.save()
            }

            return primary
        }

        let created = AppLocalSettings()
        context.insert(created)
        try context.save()
        return created
    }

    public func setCurrentUser(id: String, provider: AuthProvider) throws {
        let currentSettings = try settings()
        currentSettings.currentUserId = id
        currentSettings.lastSignedInProviderRaw = provider.rawValue
        try context.save()
    }

    public func clearCurrentUser() throws {
        let currentSettings = try settings()
        currentSettings.currentUserId = nil
        currentSettings.validatedReferralCount = 0
        currentSettings.referralRewardCount = 0
        currentSettings.claimedReferralCode = nil
        currentSettings.referralInviteCode = nil
        currentSettings.referralInviteURLString = nil
        currentSettings.referralShareCount = 0
        try context.save()
    }

    public func notificationPromptState() throws -> NotificationPromptState {
        let currentSettings = try settings()
        guard let rawValue = currentSettings.notificationPromptStateRaw else {
            return .neverAsked
        }
        return NotificationPromptState(rawValue: rawValue) ?? .neverAsked
    }

    public func setNotificationPromptState(_ state: NotificationPromptState, promptedAt: Date? = nil) throws {
        let currentSettings = try settings()
        currentSettings.notificationPromptStateRaw = state.rawValue
        if let promptedAt {
            currentSettings.notificationPromptedAt = promptedAt
        }
        try context.save()
    }

    public func notificationAuthorizationStatus() throws -> NotificationAuthorizationStatus {
        let currentSettings = try settings()
        guard let rawValue = currentSettings.notificationAuthorizationStatusRaw else {
            return .notDetermined
        }
        return NotificationAuthorizationStatus(rawValue: rawValue) ?? .notDetermined
    }

    public func setNotificationAuthorizationStatus(_ status: NotificationAuthorizationStatus) throws {
        let currentSettings = try settings()
        currentSettings.notificationAuthorizationStatusRaw = status.rawValue
        try context.save()
    }

    public func lastActiveAt() throws -> Date? {
        try settings().lastActiveAt
    }

    public func setLastActiveAt(_ date: Date) throws {
        let currentSettings = try settings()
        currentSettings.lastActiveAt = date
        try context.save()
    }

    public func hasAcceptedScanConsent(version: String) throws -> Bool {
        let currentSettings = try settings()
        return currentSettings.scanConsentVersion == version && currentSettings.scanConsentAcceptedAt != nil
    }

    public func scanConsentAcceptedAt() throws -> Date? {
        try settings().scanConsentAcceptedAt
    }

    public func setScanConsentAccepted(version: String, acceptedAt: Date = .now) throws {
        let currentSettings = try settings()
        currentSettings.scanConsentVersion = version
        currentSettings.scanConsentAcceptedAt = acceptedAt
        try context.save()
    }

    public func pendingReferralCode() throws -> String? {
        try settings().pendingReferralCode
    }

    public func setPendingReferralCode(_ code: String?) throws {
        let currentSettings = try settings()
        currentSettings.pendingReferralCode = code
        try context.save()
    }

    public func referralState() throws -> CachedReferralState {
        let currentSettings = try settings()
        return CachedReferralState(
            shareCount: currentSettings.referralShareCount ?? 0,
            validatedReferralCount: currentSettings.validatedReferralCount ?? 0,
            rewardCount: currentSettings.referralRewardCount ?? 0,
            claimedCode: currentSettings.claimedReferralCode,
            inviteCode: currentSettings.referralInviteCode,
            inviteURLString: currentSettings.referralInviteURLString,
            pendingCode: currentSettings.pendingReferralCode
        )
    }

    @discardableResult
    public func incrementReferralShareCount() throws -> Int {
        let currentSettings = try settings()
        currentSettings.referralShareCount = (currentSettings.referralShareCount ?? 0) + 1
        try context.save()
        return currentSettings.referralShareCount ?? 0
    }

    public func saveReferralStatus(_ status: RemoteReferralStatus) throws {
        let currentSettings = try settings()
        currentSettings.validatedReferralCount = status.validatedReferralCount
        currentSettings.referralRewardCount = status.rewardCount
        currentSettings.claimedReferralCode = status.claimedCode
        currentSettings.referralInviteCode = status.inviteCode
        currentSettings.referralInviteURLString = status.inviteURLString
        try context.save()
    }

    public func clearCachedReferralStatus() throws {
        let currentSettings = try settings()
        currentSettings.validatedReferralCount = 0
        currentSettings.referralRewardCount = 0
        currentSettings.claimedReferralCode = nil
        currentSettings.referralInviteCode = nil
        currentSettings.referralInviteURLString = nil
        currentSettings.referralShareCount = 0
        currentSettings.pendingReferralCode = nil
        try context.save()
    }
}
