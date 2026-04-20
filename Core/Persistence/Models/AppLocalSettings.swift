import Foundation
import SwiftData

@Model
public final class AppLocalSettings {
    @Attribute(.unique) public var id: String
    public var currentUserId: String?
    public var lastSignedInProviderRaw: String?
    public var notificationPromptStateRaw: String?
    public var notificationPromptedAt: Date?
    public var notificationAuthorizationStatusRaw: String?
    public var lastActiveAt: Date?
    public var scanConsentVersion: String?
    public var scanConsentAcceptedAt: Date?
    public var pendingReferralCode: String?
    public var referralShareCount: Int?
    public var validatedReferralCount: Int?
    public var referralRewardCount: Int?
    public var claimedReferralCode: String?
    public var referralInviteCode: String?
    public var referralInviteURLString: String?

    public init(
        id: String = AppLocalSettings.singletonId,
        currentUserId: String? = nil,
        lastSignedInProviderRaw: String? = nil,
        notificationPromptStateRaw: String? = nil,
        notificationPromptedAt: Date? = nil,
        notificationAuthorizationStatusRaw: String? = nil,
        lastActiveAt: Date? = nil,
        scanConsentVersion: String? = nil,
        scanConsentAcceptedAt: Date? = nil,
        pendingReferralCode: String? = nil,
        referralShareCount: Int? = nil,
        validatedReferralCount: Int? = nil,
        referralRewardCount: Int? = nil,
        claimedReferralCode: String? = nil,
        referralInviteCode: String? = nil,
        referralInviteURLString: String? = nil
    ) {
        self.id = id
        self.currentUserId = currentUserId
        self.lastSignedInProviderRaw = lastSignedInProviderRaw
        self.notificationPromptStateRaw = notificationPromptStateRaw
        self.notificationPromptedAt = notificationPromptedAt
        self.notificationAuthorizationStatusRaw = notificationAuthorizationStatusRaw
        self.lastActiveAt = lastActiveAt
        self.scanConsentVersion = scanConsentVersion
        self.scanConsentAcceptedAt = scanConsentAcceptedAt
        self.pendingReferralCode = pendingReferralCode
        self.referralShareCount = referralShareCount
        self.validatedReferralCount = validatedReferralCount
        self.referralRewardCount = referralRewardCount
        self.claimedReferralCode = claimedReferralCode
        self.referralInviteCode = referralInviteCode
        self.referralInviteURLString = referralInviteURLString
    }

    public static let singletonId = "app-local-settings"
}
