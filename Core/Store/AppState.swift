import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import SwiftUI
import UIKit

public enum AppRoute: Hashable {
    case auth
    case onboardingGender
    case onboardingTheme
    case onboardingSkintype
    case onboardingGoal
    case onboardingRoutine
    case onboardingRating
    case onboardingTransition
    case home
    case upload
    case scanPrep(useCamera: Bool)
    case shareGate
    case loadingAnalysis
    case paywall
}

private enum ImageFingerprint {
    static func stableHash(for imageData: Data) -> String? {
        guard let image = UIImage(data: imageData) else { return nil }

        let normalized = normalizedJPEGData(from: image) ?? imageData
        let digest = SHA256.hash(data: normalized)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedJPEGData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let size = image.size
        let longestSide = max(size.width, size.height)

        let targetImage: UIImage
        if longestSide > maxDimension {
            let scale = maxDimension / longestSide
            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            targetImage = image
        }

        return targetImage.jpegData(compressionQuality: 0.82)
    }
}

private enum HomeErrorContext {
    case deleteAccount
    case recentAnalysesLoad
    case skinJourneyLoad
    case skinJourneySave
    case skinJourneySaveSync
    case skinJourneyDelete
    case skinJourneyDeleteSync
    case cloudSync
    case recentAnalysesSync
    case skinJourneySync
}

private struct ScoreStabilizationDecision {
    let stabilizedScore: Double
    let referenceScore: Double
    let neighborCount: Int
    let maxNeighborDistance: Double
}

private struct SimilarAnalysisNeighbor {
    let score: Double
    let distance: Double
    let createdAt: Date
}

private enum BillingErrorOrigin {
    case entitlement
    case packages
    case checkout
}

#if DEBUG
private let RESET_ONBOARDING_EACH_LAUNCH = false
private let FORCE_DEBUG_PRO_ACCESS = false
private let DEBUG_PRO_PLAN_ID = "debug.pro.testing"
#else
private let RESET_ONBOARDING_EACH_LAUNCH = false
private let FORCE_DEBUG_PRO_ACCESS = false
private let DEBUG_PRO_PLAN_ID = ""
#endif

private let nonOverrideableQualityReasons: Set<SkinImageQualityReason> = [
    .noFace,
    .multipleFaces
]

@MainActor
public class AppState: ObservableObject {
    private static let analysisCacheVersion = "2026-03-07-iterative-elimination-v1"
    private let authService: AuthService
    private let onboardingDraftRepository: OnboardingDraftRepository
    private let onboardingRepository: OnboardingRepository
    private let analysisRepository: AnalysisRepository
    private let skinJourneyRepository: SkinJourneyRepository
    private let analysisPhotoStore: AnalysisPhotoStoring
    private let settingsRepository: SettingsRepository
    private let notificationService: NotificationService
    private let billingService: BillingService
    private let skinAnalysisService: SkinAnalysisService
    private let qualityOverrideAnalysisService: (any SkinAnalysisQualityOverrideService)?
    private let faceDetectionService: FaceDetectionService
    private let remoteOnboardingRepository: RemoteOnboardingRepository?
    private let remoteScanRepository: RemoteScanRepository?
    private let remoteJourneyRepository: RemoteJourneyRepository?
    private let remoteReferralRepository: RemoteReferralRepository?
    private var paywallRefreshTask: Task<Void, Never>?
    private var billingErrorOrigin: BillingErrorOrigin?
    private var hasResolvedBillingState = false
    private var pendingScanImageData: Data?
    private var pendingScanAllowsCacheReuse = false
    private var pendingAcceptedQualityWarningReasons: Set<SkinImageQualityReason> = []
    private var pendingAnalysisTask: Task<String?, Never>?
    private var shouldAutoClaimPendingReferralCode = false
    private var homeErrorContext: HomeErrorContext?

    @Published public var currentRoute: [AppRoute] = []
    @Published public var isAuthenticated: Bool = false
    @Published public var hasCompletedOnboarding: Bool = false
    @AppStorage("appTheme") public var appTheme: String = "pastel"
    @Published public var isBootstrapping: Bool = true
    @Published public var isAuthLoading: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var homeErrorMessage: String? = nil
    @Published public var launchWarningMessage: String? = nil
    @Published public var scanErrorMessage: String? = nil
    @Published public var scanErrorReasons: [SkinImageQualityReason] = []
    @Published public var shouldOpenHomeDeepDive: Bool = false
    @Published public var homeDeepDiveAnalysisId: String? = nil
    @Published public var currentSession: AuthSession? = nil
    @Published public var isGoogleConfigured: Bool = false
    @Published public var onboardingDraftGender: String? = nil
    @Published public var onboardingDraftSkinTypes: Set<String> = []
    @Published public var onboardingDraftGoal: String? = nil
    @Published public var onboardingDraftRoutine: String? = nil
    @Published public var recentAnalyses: [LocalAnalysis] = []
    @Published public var analysisCalendarEntries: [AnalysisCalendarEntry] = []
    @Published public var totalScanCount: Int = 0
    @Published public var scanDayStreakCount: Int = 0
    @Published public var skinJourneyLogs: [SkinJourneyLog] = []
    @Published public var notificationPromptState: NotificationPromptState = .neverAsked
    @Published public var hasAcceptedCurrentScanConsent: Bool = false
    @Published public var scanConsentAcceptedAt: Date? = nil
    @Published public var pendingReferralCode: String? = nil
    @Published public var referralShareCount: Int = 0
    @Published public var validatedReferralCount: Int = 0
    @Published public var referralRewardCount: Int = 0
    @Published public var claimedReferralCode: String? = nil
    @Published public var referralInviteCode: String? = nil
    @Published public var referralInviteURLString: String? = nil
    @Published public var isReferralLoading: Bool = false
    @Published public var referralErrorMessage: String? = nil
    @Published public var referralSuccessMessage: String? = nil

    @Published public var isProActive: Bool = false
    @Published public var subscriptionPlanId: String? = nil
    @Published public var subscriptionExpiry: Date? = nil
    @Published public var paywallPackages: [PaywallPackage] = []
    @Published public var isPaywallPackagesLoading: Bool = false
    @Published public var isPaywallLoading: Bool = false
    @Published public var billingErrorMessage: String? = nil
    @Published public var debugHasStoredBackendSession: Bool = false
    @Published public var debugGuestBackendSessionError: String? = nil

    public var debugBackendEndpoint: String {
        AppConfig.backendBaseURL()
    }

    public static var freeScanQuota: Int {
        AppConfig.freeScanQuota()
    }

    public var hasUnlimitedScans: Bool {
        AppConfig.isUnlimitedScansMode()
    }

    public var allowsGuestAccess: Bool {
        true
    }

    public var isGuestSession: Bool {
        currentSession?.provider == .guest
    }

    public var referralBonusScansEarned: Int {
        max(
            referralRewardCount,
            Self.referralBonusScansEarned(validatedReferralCount: validatedReferralCount)
        )
    }

    public var totalFreeScanAllowance: Int {
        if hasUnlimitedScans {
            return Int.max
        }
        return Self.freeScanQuota
    }

    public var consumedFreeScans: Int {
        if hasUnlimitedScans {
            return 0
        }
        return max(0, totalScanCount)
    }

    public var validatedReferralsUntilNextFreeScan: Int {
        let threshold = AppConfig.referralRewardThreshold
        let progress = validatedReferralCount % threshold
        return progress == 0 ? threshold : max(1, threshold - progress)
    }

    public var remainingFreeScans: Int {
        if hasUnlimitedScans {
            return Int.max
        }
        return max(0, totalFreeScanAllowance - consumedFreeScans)
    }

    public var canRunScan: Bool {
        hasUnlimitedScans || isProActive || consumedFreeScans < totalFreeScanAllowance
    }

    public var canForceAnalyzeCurrentScan: Bool {
        guard pendingScanImageData != nil, qualityOverrideAnalysisService != nil else {
            return false
        }

        let currentReasons = Set(scanErrorReasons)
        guard !currentReasons.isEmpty else {
            return false
        }
        guard currentReasons.isDisjoint(with: nonOverrideableQualityReasons) else {
            return false
        }

        return true
    }

    public var canEarnReferralRewards: Bool {
        guard AppConfig.isReferralsEnabled() else { return false }
        guard let session = currentSession else { return false }
        return session.provider != .guest
    }

    public var hasValidScanSession: Bool {
        guard let session = currentSession else { return false }
        return session.usesRemoteBackend && authService.hasStoredBackendSession
    }

    public var currentSkinAnalysisContext: SkinAnalysisUserContext? {
        currentSkinAnalysisUserContext()
    }

    public var referralInviteURL: URL? {
        guard let referralInviteURLString else { return nil }
        return URL(string: referralInviteURLString)
    }

    public var hasPendingReferralCode: Bool {
        AppConfig.normalizedReferralCode(pendingReferralCode) != nil
    }

    public var referralShareItems: [Any] {
        AppConfig.referralShareSheetItems(
            inviteURL: referralInviteURL,
            inviteCode: referralInviteCode
        )
    }

    public var genericShareItems: [Any] {
        AppConfig.genericShareSheetItems()
    }

    public static func referralBonusScansEarned(validatedReferralCount: Int) -> Int {
        guard validatedReferralCount > 0 else { return 0 }
        return validatedReferralCount / AppConfig.referralRewardThreshold
    }

    public init(
        authService: AuthService,
        onboardingDraftRepository: OnboardingDraftRepository,
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        skinJourneyRepository: SkinJourneyRepository,
        analysisPhotoStore: AnalysisPhotoStoring = FileSystemAnalysisPhotoStore(),
        settingsRepository: SettingsRepository,
        notificationService: NotificationService,
        billingService: BillingService,
        skinAnalysisService: SkinAnalysisService,
        qualityOverrideAnalysisService: (any SkinAnalysisQualityOverrideService)? = nil,
        faceDetectionService: FaceDetectionService,
        remoteOnboardingRepository: RemoteOnboardingRepository? = nil,
        remoteScanRepository: RemoteScanRepository? = nil,
        remoteJourneyRepository: RemoteJourneyRepository? = nil,
        remoteReferralRepository: RemoteReferralRepository? = nil,
        launchWarningMessage: String? = nil
    ) {
        self.authService = authService
        self.onboardingDraftRepository = onboardingDraftRepository
        self.onboardingRepository = onboardingRepository
        self.analysisRepository = analysisRepository
        self.skinJourneyRepository = skinJourneyRepository
        self.analysisPhotoStore = analysisPhotoStore
        self.settingsRepository = settingsRepository
        self.notificationService = notificationService
        self.billingService = billingService
        self.skinAnalysisService = skinAnalysisService
        self.qualityOverrideAnalysisService = qualityOverrideAnalysisService
        self.faceDetectionService = faceDetectionService
        self.remoteOnboardingRepository = remoteOnboardingRepository
        self.remoteScanRepository = remoteScanRepository
        self.remoteJourneyRepository = remoteJourneyRepository
        self.remoteReferralRepository = remoteReferralRepository
        self.isGoogleConfigured = authService.isGoogleSignInAvailable
        self.launchWarningMessage = launchWarningMessage
    }

    public func navigate(to route: AppRoute) {
        if case .shareGate = route, !AppConfig.isReferralsEnabled() {
            return
        }
        currentRoute.append(route)
    }

    public func presentAsRoot(_ root: AppRoute) {
        currentRoute = [root]
    }

    public func goBack() {
        if !currentRoute.isEmpty {
            currentRoute.removeLast()
        }
    }

    public func openPaywall() {
        if currentRoute.last != .paywall {
            navigate(to: .paywall)
        }
        Task {
            await refreshPaywallData()
        }
    }

    public func bootstrap() async {
        isBootstrapping = true
        isGoogleConfigured = authService.isGoogleSignInAvailable
        defer { isBootstrapping = false }

        loadStoredNotificationPromptState()
        loadPersistedLaunchSettings()

        let restoredSession = await authService.restoreSession()
        guard let restoredSession else {
            do {
                let guestSession = try await authService.continueAsGuestForBootstrap()
                authErrorMessage = nil
                await setAuthenticatedState(with: guestSession)
                return
            } catch {
                authErrorMessage = userFacingError(from: error)
                synchronizeDebugAuthDiagnostics()
            }
            await notificationService.cancelReengagementNotifications()
            _ = notificationService.consumePendingOpenIntent()
            resetSessionStateToSignedOut()
            presentAsRoot(.auth)
            return
        }

#if DEBUG
        if RESET_ONBOARDING_EACH_LAUNCH {
            try? onboardingRepository.resetOnboarding(userId: restoredSession.localUserId)
            try? onboardingDraftRepository.deleteDraft(userId: restoredSession.localUserId)
        }
#endif

        _ = await synchronizeNotificationAuthorizationStatus()
        await setAuthenticatedState(with: restoredSession)
    }

    public func signInWithApple(result: Result<ASAuthorization, Error>) async {
        isAuthLoading = true
        authErrorMessage = nil
        defer { isAuthLoading = false }

        do {
            let session = try await authService.signInWithApple(result: result)
            await setAuthenticatedState(with: session)
        } catch {
            authErrorMessage = userFacingError(from: error)
            synchronizeDebugAuthDiagnostics()
        }
    }

    public func signInWithGoogle() async {
        isAuthLoading = true
        authErrorMessage = nil
        defer { isAuthLoading = false }

        do {
            let session = try await authService.signInWithGoogle()
            await setAuthenticatedState(with: session)
        } catch {
            authErrorMessage = userFacingError(from: error)
            synchronizeDebugAuthDiagnostics()
        }
    }

    public func continueAsGuest() async {
        isAuthLoading = true
        authErrorMessage = nil
        defer { isAuthLoading = false }

        do {
            let session = try await authService.continueAsGuest()
            await setAuthenticatedState(with: session)
        } catch {
            authErrorMessage = userFacingError(from: error)
            synchronizeDebugAuthDiagnostics()
        }
    }

    public func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            authErrorMessage = userFacingError(from: error)
        }

        await notificationService.cancelReengagementNotifications()
        _ = notificationService.consumePendingOpenIntent()
        try? settingsRepository.clearCachedReferralStatus()
        resetSessionStateToSignedOut()
        await transitionToGuestSession()
    }

    public func deleteAccount() async {
        do {
            try await authService.deleteAccount()
            clearHomeError(for: .deleteAccount)
            await notificationService.cancelReengagementNotifications()
            _ = notificationService.consumePendingOpenIntent()
            try? settingsRepository.clearCachedReferralStatus()
            resetSessionStateToSignedOut()
            await transitionToGuestSession()
        } catch {
            setHomeError(userFacingError(from: error), context: .deleteAccount)
        }
    }

    public func clearHomeErrorMessage() {
        homeErrorMessage = nil
        homeErrorContext = nil
    }

    public func clearScanErrorMessage() {
        clearScanError()
    }

    public func dismissLaunchWarning() {
        launchWarningMessage = nil
    }

    @discardableResult
    public func acceptCurrentScanConsentIfNeeded() -> Bool {
        guard !hasAcceptedCurrentScanConsent else { return true }

        let acceptedAt = Date()
        do {
            try settingsRepository.setScanConsentAccepted(
                version: AppConfig.scanConsentVersion,
                acceptedAt: acceptedAt
            )
            hasAcceptedCurrentScanConsent = true
            scanConsentAcceptedAt = acceptedAt
            return true
        } catch {
            return false
        }
    }

    public func openUploadFlow() {
        guard ensureAuthenticatedScanAvailability() else { return }
        navigate(to: .upload)
    }

    public func openScanPrep(useCamera: Bool) {
        guard ensureAuthenticatedScanAvailability() else { return }
        guard canRunScan else {
            openPaywall()
            return
        }
        navigate(to: .scanPrep(useCamera: useCamera))
    }

    @discardableResult
    public func ensureAuthenticatedScanAvailability(redirectToAuth: Bool = false) -> Bool {
        guard let session = currentSession, session.isSignedIn else {
            setScanError("SkinLit is still preparing your local session. Try again in a moment.")
            return false
        }

        guard session.usesRemoteBackend, authService.hasStoredBackendSession else {
            if session.provider == .guest {
                setScanError("Cloud analysis is temporarily unavailable. Try again in a moment.")
            } else {
                let message = "Your cloud beta session expired. Activate cloud again to keep saving online."
                setScanError(message)
                if redirectToAuth {
                    authErrorMessage = message
                    navigate(to: .auth)
                }
            }
            return false
        }

        clearScanError()
        return true
    }

    public func handleIncomingURL(_ url: URL) {
        guard AppConfig.isReferralsEnabled() else { return }
        guard let referralCode = AppConfig.referralCode(from: url) else { return }

        do {
            try settingsRepository.setPendingReferralCode(referralCode)
            pendingReferralCode = referralCode
            referralErrorMessage = nil
            referralSuccessMessage = referralCaptureMessage(for: referralCode)
            shouldAutoClaimPendingReferralCode = true
        } catch {
            referralErrorMessage = "Could not save that invite code right now."
            return
        }

        guard isAuthenticated, hasCompletedOnboarding else { return }
        Task {
            await claimPendingReferralCode(autoTriggered: true)
        }
    }

    public func updatePendingReferralCode(_ code: String) {
        let normalizedCode = AppConfig.normalizedReferralCode(code) ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        pendingReferralCode = normalizedCode.isEmpty ? nil : normalizedCode
        referralErrorMessage = nil
        referralSuccessMessage = nil

        do {
            try settingsRepository.setPendingReferralCode(pendingReferralCode)
        } catch {
            referralErrorMessage = "Could not save that invite code right now."
        }
    }

    public func clearPendingReferralCode() {
        pendingReferralCode = nil
        shouldAutoClaimPendingReferralCode = false

        do {
            try settingsRepository.setPendingReferralCode(nil)
        } catch {
            referralErrorMessage = "Could not clear that invite code right now."
        }
    }

    public func claimPendingReferralCode() async {
        await claimPendingReferralCode(autoTriggered: false)
    }

    public func prepareReferralInvite() async -> Bool {
        referralErrorMessage = nil

        guard AppConfig.isReferralsEnabled() else {
            referralErrorMessage = "Referral rewards are unavailable right now."
            return false
        }

        guard AppConfig.isShareConfigured() else {
            return false
        }

        guard canEarnReferralRewards else {
            referralErrorMessage = "Activate cloud beta with Apple or Google before sharing referral links."
            return false
        }

        if referralInviteURL != nil && referralInviteCode != nil {
            return true
        }

        guard shouldUseRemoteBackend(for: currentSession), let remoteReferralRepository else {
            referralErrorMessage = "Referral links are unavailable right now."
            return false
        }

        isReferralLoading = true
        defer { isReferralLoading = false }

        do {
            let status = try await remoteReferralRepository.createInvite()
            try settingsRepository.saveReferralStatus(status)
            applyReferralStatus(status, preservePendingCode: true)
            return referralInviteURL != nil
        } catch {
            referralErrorMessage = "Could not load your invite link right now."
            return false
        }
    }

    public func setOnboardingGender(_ gender: String?) {
        onboardingDraftGender = gender
        persistOnboardingDraft(lastCompletedStep: .gender)
    }

    public func setOnboardingSkinTypes(_ skinTypes: Set<String>) {
        onboardingDraftSkinTypes = skinTypes
        persistOnboardingDraft(lastCompletedStep: .skintype)
    }

    public func setOnboardingGoal(_ goal: String?) {
        onboardingDraftGoal = goal
        persistOnboardingDraft(lastCompletedStep: .goal)
    }

    public func setOnboardingRoutine(_ routine: String?) {
        onboardingDraftRoutine = routine
        persistOnboardingDraft(lastCompletedStep: .routine)
    }

    public func completeOnboardingThemeSelection() {
        persistOnboardingDraft(lastCompletedStep: .theme)
    }

    public var shouldPromptForNotificationPermission: Bool {
        notificationPromptState == .neverAsked
    }

    public func recordNotificationSoftDecline() async {
        let promptedAt = Date()
        do {
            try settingsRepository.setNotificationPromptState(.softDeclined, promptedAt: promptedAt)
            try settingsRepository.setNotificationAuthorizationStatus(.notDetermined)
            notificationPromptState = .softDeclined
        } catch {}

        await notificationService.cancelReengagementNotifications()
    }

    public func requestNotificationAuthorizationFromOnboarding() async {
        let promptedAt = Date()
        let promptResult = await notificationService.requestAuthorization()

        do {
            try settingsRepository.setNotificationPromptState(promptResult, promptedAt: promptedAt)
            notificationPromptState = promptResult
        } catch {}

        let authorizationStatus = await synchronizeNotificationAuthorizationStatus()
        if authorizationStatus.isAuthorized {
            await refreshReengagementNotifications()
        } else {
            await notificationService.cancelReengagementNotifications()
        }
    }

    public func handleScenePhase(_ scenePhase: ScenePhase) async {
        guard scenePhase == .active else { return }

        do {
            try settingsRepository.setLastActiveAt(.now)
        } catch {}

        _ = await synchronizeNotificationAuthorizationStatus()

        if currentSession != nil {
            await refreshBillingState()
            await refreshReengagementNotifications()
            await consumePendingNotificationIntentIfNeeded()
        } else {
            await notificationService.cancelReengagementNotifications()
            _ = notificationService.consumePendingOpenIntent()
        }
    }

    public func completeOnboardingFromDraft() async {
        guard let session = currentSession else { return }
        guard
            !onboardingDraftSkinTypes.isEmpty,
            let goal = onboardingDraftGoal,
            let routine = onboardingDraftRoutine
        else {
            authErrorMessage = "Please complete all onboarding steps before continuing."
            return
        }

        do {
            try onboardingRepository.saveOnboarding(
                userId: session.localUserId,
                skinTypes: onboardingDraftSkinTypes.sorted(),
                goal: goal,
                routine: routine
            )
            if shouldUseRemoteBackend(for: session) {
                try await remoteOnboardingRepository?.saveProfile(
                    skinTypes: onboardingDraftSkinTypes.sorted(),
                    goal: goal,
                    routineLevel: routine
                )
            }
            try onboardingDraftRepository.deleteDraft(userId: session.localUserId)
            hasCompletedOnboarding = true
            clearOnboardingDraft()
            try loadRecentAnalyses(for: session.localUserId)
            try loadSkinJourneyLogs(for: session.localUserId)
            presentAsRoot(.home)
            await refreshPaywallData()
            await refreshReferralState(createInviteIfMissing: false)
            await refreshReengagementNotifications()
            if shouldAutoClaimPendingReferralCode {
                await claimPendingReferralCode(autoTriggered: true)
            }
        } catch {
            authErrorMessage = "Could not save onboarding preferences."
        }
    }

    public func persistAnalysis(
        id: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String? = nil,
        criteria: [String: Double],
        criterionInsights: [String: SkinCriterionInsight]? = nil,
        debugMetadata: LocalAnalysisDebugMetadata? = nil
    ) {
        guard let userId = currentSession?.localUserId else { return }
        do {
            try saveAnalysisCache(
                id: id,
                userId: userId,
                score: score,
                summary: summary,
                skinTypeDetected: skinTypeDetected,
                imageHash: imageHash,
                criteria: criteria,
                criterionInsights: criterionInsights,
                debugMetadata: debugMetadata
            )
            try loadRecentAnalyses(for: userId)
            Task {
                await refreshReengagementNotifications()
            }
        } catch {
            authErrorMessage = "Could not save this analysis."
        }
    }

    private func saveAnalysisCache(
        id: String,
        userId: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String?,
        criteria: [String: Double],
        criterionInsights: [String: SkinCriterionInsight]? = nil,
        debugMetadata: LocalAnalysisDebugMetadata? = nil,
        localImageRelativePath: String? = nil,
        createdAt: Date? = nil
    ) throws {
        let existingCreatedAt = try analysisRepository.analysis(byId: id)?.createdAt
        let evaluationDate = createdAt ?? existingCreatedAt ?? .now
        let stabilityDecision = try makeScoreStabilizationDecision(
            analysisID: id,
            userId: userId,
            rawScore: score,
            criteria: criteria,
            createdAt: evaluationDate
        )
        let persistedScore = stabilityDecision?.stabilizedScore ?? Self.round1(score)
        let persistedDebugMetadata = mergedDebugMetadata(
            from: debugMetadata,
            rawScore: score,
            persistedScore: persistedScore,
            stabilizationDecision: stabilityDecision
        )
        let criteriaData = try JSONEncoder().encode(criteria)
        let criteriaJSON = String(data: criteriaData, encoding: .utf8) ?? "{}"
        let criterionInsightsJSON = try encodeCriterionInsights(criterionInsights)
        let debugMetadataJSON = try encodeDebugMetadata(persistedDebugMetadata)
        try analysisRepository.saveAnalysis(
            id: id,
            userId: userId,
            score: persistedScore,
            summary: summary,
            skinTypeDetected: skinTypeDetected,
            imageHash: imageHash,
            localImageRelativePath: localImageRelativePath,
            criteriaJSON: criteriaJSON,
            criterionInsightsJSON: criterionInsightsJSON,
            debugMetadataJSON: debugMetadataJSON,
            createdAt: createdAt
        )
    }

    private func makeScoreStabilizationDecision(
        analysisID: String,
        userId: String,
        rawScore: Double,
        criteria: [String: Double],
        createdAt: Date
    ) throws -> ScoreStabilizationDecision? {
        let roundedRawScore = Self.round1(scoreClamped(rawScore))
        let neighbors = try analysisRepository.fetchAllAnalyses(userId: userId)
            .compactMap { analysis -> SimilarAnalysisNeighbor? in
                guard analysis.id != analysisID else { return nil }
                guard Self.daysBetween(analysis.createdAt, createdAt) <= 21 else { return nil }
                let distance = Self.criteriaDistance(
                    between: criteria,
                    and: decodedCriteria(from: analysis)
                )
                guard distance <= 0.9 else { return nil }
                return SimilarAnalysisNeighbor(
                    score: analysis.score,
                    distance: distance,
                    createdAt: analysis.createdAt
                )
            }
            .sorted { left, right in
                if left.distance == right.distance {
                    return abs(left.createdAt.timeIntervalSince(createdAt)) < abs(right.createdAt.timeIntervalSince(createdAt))
                }
                return left.distance < right.distance
            }

        guard !neighbors.isEmpty else { return nil }

        let selectedNeighbors = Array(neighbors.prefix(4))
        let nearestDistance = selectedNeighbors.first?.distance ?? 1
        guard selectedNeighbors.count >= 2 || nearestDistance <= 0.35 else { return nil }

        let referenceScore = Self.weightedReferenceScore(from: selectedNeighbors)
        let rawDelta = referenceScore - roundedRawScore
        guard abs(rawDelta) >= 1.2 else { return nil }

        let similarityStrength = max(0.35, 1 - min(nearestDistance / 0.9, 1))
        let stabilizedDelta = Self.clamp(rawDelta * (0.42 * similarityStrength), min: -0.7, max: 0.7)
        guard abs(stabilizedDelta) >= 0.15 else { return nil }

        let stabilizedScore = Self.round1(scoreClamped(roundedRawScore + stabilizedDelta))
        guard stabilizedScore != roundedRawScore else { return nil }

        return ScoreStabilizationDecision(
            stabilizedScore: stabilizedScore,
            referenceScore: Self.round1(referenceScore),
            neighborCount: selectedNeighbors.count,
            maxNeighborDistance: nearestDistance
        )
    }

    private func mergedDebugMetadata(
        from debugMetadata: LocalAnalysisDebugMetadata?,
        rawScore: Double,
        persistedScore: Double,
        stabilizationDecision: ScoreStabilizationDecision?
    ) -> LocalAnalysisDebugMetadata? {
        guard let stabilizationDecision else {
            return debugMetadata
        }

        let baselineScore = Self.round1(scoreClamped(debugMetadata?.finalScore ?? rawScore))
        let adjustmentDelta = Self.round1(persistedScore - baselineScore)
        let stabilizationReason =
            "Score stabilized against \(stabilizationDecision.neighborCount) similar recent scan" +
            (stabilizationDecision.neighborCount == 1 ? "" : "s") +
            " to reduce jumps between near-identical selfies."

        return LocalAnalysisDebugMetadata(
            analysisVersion: debugMetadata?.analysisVersion,
            predictedBand: predictedBand(for: persistedScore),
            observedConditions: debugMetadata?.observedConditions,
            imageQualityStatus: debugMetadata?.imageQualityStatus,
            imageQualityReasons: debugMetadata?.imageQualityReasons ?? [],
            referenceCatalogVersion: debugMetadata?.referenceCatalogVersion,
            baseScore: baselineScore,
            finalScore: persistedScore,
            adjustmentDelta: adjustmentDelta,
            matchedReferenceIDs: debugMetadata?.matchedReferenceIDs,
            verificationVerdict: adjustmentDelta >= 0 ? .adjustUp : .adjustDown,
            adjustmentReason: stabilizationReason,
            localStabilityAdjustmentApplied: true,
            localStabilityReferenceScore: stabilizationDecision.referenceScore,
            localStabilityNeighborCount: stabilizationDecision.neighborCount,
            qualityOverrideAccepted: debugMetadata?.qualityOverrideAccepted,
            qualityOverrideAcceptedReasons: debugMetadata?.qualityOverrideAcceptedReasons,
            qualityOverrideLabel: debugMetadata?.qualityOverrideLabel,
            model: debugMetadata?.model,
            source: debugMetadata?.source ?? .unknown
        )
    }

    private func persistCachedAnalysisAsFreshScan(
        _ existing: LocalAnalysis,
        userId: String,
        imageHash: String?,
        imageData: Data
    ) throws -> String {
        let duplicatedAnalysisID = UUID().uuidString
        let criteria = decodedCriteria(from: existing)
        let debugMetadata = localCacheDebugMetadata(from: existing)

        try saveAnalysisCache(
            id: duplicatedAnalysisID,
            userId: userId,
            score: existing.score,
            summary: existing.summary,
            skinTypeDetected: existing.skinTypeDetected,
            imageHash: imageHash,
            criteria: criteria,
            criterionInsights: existing.criterionInsights,
            debugMetadata: debugMetadata,
            createdAt: .now
        )

        _ = cacheProcessedPhotoIfPossible(analysisID: duplicatedAnalysisID, imageData: imageData)
        return duplicatedAnalysisID
    }

    @discardableResult
    private func cacheProcessedPhotoIfPossible(analysisID: String, imageData: Data) -> Bool {
        do {
            let localImageRelativePath = try analysisPhotoStore.saveProcessedPhoto(
                imageData,
                analysisID: analysisID
            )
            try analysisRepository.updateAnalysisLocalImagePath(
                id: analysisID,
                localImageRelativePath: localImageRelativePath
            )
            return true
        } catch {
            return false
        }
    }

    private func resetPendingScanQualityOverride() {
        pendingAcceptedQualityWarningReasons = []
    }

    private func acceptedQualityOverrideDebugMetadata(
        base: LocalAnalysisDebugMetadata? = nil,
        acceptedReasons: Set<SkinImageQualityReason>
    ) -> LocalAnalysisDebugMetadata {
        let orderedReasons = SkinImageQualityReason.allCases.filter { acceptedReasons.contains($0) }
        let label = orderedReasons.contains(.heavyMakeup) ? "with makeup" : "manual quality override"

        return LocalAnalysisDebugMetadata(
            analysisVersion: base?.analysisVersion ?? AppConfig.skinAnalysisVersion,
            predictedBand: base?.predictedBand,
            observedConditions: base?.observedConditions,
            imageQualityStatus: base?.imageQualityStatus ?? .insufficient,
            imageQualityReasons: orderedReasons,
            referenceCatalogVersion: base?.referenceCatalogVersion ?? AppConfig.referenceCatalogVersion,
            baseScore: base?.baseScore,
            finalScore: base?.finalScore,
            adjustmentDelta: base?.adjustmentDelta,
            matchedReferenceIDs: base?.matchedReferenceIDs,
            verificationVerdict: base?.verificationVerdict,
            adjustmentReason: base?.adjustmentReason ?? "User accepted a lower-confidence scan despite image quality warnings.",
            localStabilityAdjustmentApplied: base?.localStabilityAdjustmentApplied,
            localStabilityReferenceScore: base?.localStabilityReferenceScore,
            localStabilityNeighborCount: base?.localStabilityNeighborCount,
            qualityOverrideAccepted: true,
            qualityOverrideAcceptedReasons: orderedReasons,
            qualityOverrideLabel: label,
            model: base?.model,
            source: .qualityOverride
        )
    }

    private func parsedImageQualityReasons(from message: String) -> [SkinImageQualityReason] {
        let lowercased = message.lowercased()
        return SkinImageQualityReason.allCases.filter { lowercased.contains($0.rawValue) }
    }

    private func decodedCriteria(from analysis: LocalAnalysis) -> [String: Double] {
        guard let data = analysis.criteriaJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    public func refreshRecentAnalyses() {
        guard let userId = currentSession?.localUserId else {
            recentAnalyses = []
            analysisCalendarEntries = []
            totalScanCount = 0
            scanDayStreakCount = 0
            clearHomeError(for: .recentAnalysesLoad)
            return
        }

        do {
            try loadRecentAnalyses(for: userId)
            clearHomeError(for: .recentAnalysesLoad)
        } catch {
            setHomeError("Could not load recent analyses.", context: .recentAnalysesLoad)
        }

        if shouldUseRemoteBackend(for: currentSession) {
            Task {
                await synchronizeRemoteAnalysesIfNeeded()
            }
        }
    }

    public func refreshSkinJourneyLogs() {
        guard let userId = currentSession?.localUserId else {
            skinJourneyLogs = []
            clearHomeError(for: .skinJourneyLoad)
            return
        }

        do {
            try loadSkinJourneyLogs(for: userId)
            clearHomeError(for: .skinJourneyLoad)
        } catch {
            setHomeError("Could not load your skin journey.", context: .skinJourneyLoad)
        }

        if shouldUseRemoteBackend(for: currentSession) {
            Task {
                await synchronizeRemoteJourneyIfNeeded()
            }
        }
    }

    public func saveSkinJourneyLog(
        date: Date,
        routineStepIDs: [String],
        treatmentIDs: [String],
        skinStatusIDs: [String],
        note: String
    ) {
        guard let userId = currentSession?.localUserId else { return }

        do {
            try skinJourneyRepository.upsertLog(
                userId: userId,
                date: date,
                routineStepIDs: routineStepIDs,
                treatmentIDs: treatmentIDs,
                skinStatusIDs: skinStatusIDs,
                note: note
            )
            try loadSkinJourneyLogs(for: userId)
            if let session = currentSession, shouldUseRemoteBackend(for: session) {
                let remoteLog = RemoteJourneyLog(
                    dayKey: SkinJourneyRepository.dayKey(for: date),
                    dayStartAt: SkinJourneyRepository.startOfDay(for: date),
                    routineStepIDs: routineStepIDs,
                    treatmentIDs: treatmentIDs,
                    skinStatusIDs: skinStatusIDs,
                    note: SkinJourneyLog.trimmedNote(note),
                    createdAt: .now,
                    updatedAt: .now
                )
                Task {
                    do {
                        try await remoteJourneyRepository?.saveLog(remoteLog)
                        await MainActor.run {
                            self.clearHomeError(for: .skinJourneySaveSync)
                        }
                    } catch {
                        await MainActor.run {
                            self.setHomeError("Could not sync your skin journey.", context: .skinJourneySaveSync)
                        }
                    }
                }
            }
            clearHomeError(for: .skinJourneySave)
        } catch {
            setHomeError("Could not save your skin journey.", context: .skinJourneySave)
        }
    }

    public func deleteSkinJourneyLog(date: Date) {
        guard let userId = currentSession?.localUserId else { return }

        do {
            try skinJourneyRepository.deleteLog(userId: userId, date: date)
            try loadSkinJourneyLogs(for: userId)
            if let session = currentSession, shouldUseRemoteBackend(for: session) {
                let dayKey = SkinJourneyRepository.dayKey(for: date)
                Task {
                    do {
                        try await remoteJourneyRepository?.deleteLog(dayKey: dayKey)
                        await MainActor.run {
                            self.clearHomeError(for: .skinJourneyDeleteSync)
                        }
                    } catch {
                        await MainActor.run {
                            self.setHomeError("Could not sync the deleted skin journey entry.", context: .skinJourneyDeleteSync)
                        }
                    }
                }
            }
            clearHomeError(for: .skinJourneyDelete)
        } catch {
            setHomeError("Could not delete this skin journey log.", context: .skinJourneyDelete)
        }
    }

    public func skinJourneyLog(on date: Date) -> SkinJourneyLog? {
        let calendar = Calendar.autoupdatingCurrent
        return skinJourneyLogs.first { calendar.isDate($0.dayStartAt, inSameDayAs: date) }
    }

    public func queueScanImageData(_ imageData: Data, allowCacheReuse: Bool = true) {
        pendingScanImageData = imageData
        pendingScanAllowsCacheReuse = allowCacheReuse
        resetPendingScanQualityOverride()
        clearScanError()
    }

    public func discardPendingScanImageData() {
        pendingScanImageData = nil
        pendingScanAllowsCacheReuse = false
        resetPendingScanQualityOverride()
    }

    @discardableResult
    public func acceptCurrentScanQualityWarningForManualAnalysis() -> Bool {
        guard canForceAnalyzeCurrentScan else { return false }
        pendingAcceptedQualityWarningReasons.formUnion(scanErrorReasons)
        clearScanError()
        return true
    }

    public func processPendingAnalysis() async -> String? {
        if let pendingAnalysisTask {
            return await pendingAnalysisTask.value
        }

        let task = Task<String?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.executePendingAnalysis()
        }
        pendingAnalysisTask = task
        let result = await task.value
        pendingAnalysisTask = nil
        return result
    }

    private func executePendingAnalysis() async -> String? {
        if currentSession?.provider == .guest,
           (currentSession?.usesRemoteBackend != true || !authService.hasStoredBackendSession) {
            do {
                let refreshedGuestSession = try await authService.continueAsGuest()
                currentSession = refreshedGuestSession
                isAuthenticated = true
                clearScanError()
                synchronizeDebugAuthDiagnostics()
            } catch {
                setScanError(userFacingError(from: error))
                synchronizeDebugAuthDiagnostics()
                return nil
            }
        }

        guard let session = currentSession else {
            setScanError("SkinLit is still preparing your local session. Try again in a moment.")
            synchronizeDebugAuthDiagnostics()
            return nil
        }
        guard session.usesRemoteBackend else {
            setScanError(authService.lastGuestBackendSessionErrorDescription ?? BackendClientError.missingSession.localizedDescription)
            synchronizeDebugAuthDiagnostics()
            return nil
        }
        guard authService.hasStoredBackendSession else {
            setScanError(authService.lastGuestBackendSessionErrorDescription ?? BackendClientError.missingSession.localizedDescription)
            synchronizeDebugAuthDiagnostics()
            return nil
        }

        guard canRunScan else {
            setScanError("Your free scans are finished. Upgrade to PRO to keep scanning.")
            return nil
        }

        guard let imageData = pendingScanImageData else {
            setScanError("Select a selfie before starting analysis.")
            return nil
        }

        let rawImageHash = ImageFingerprint.stableHash(for: imageData)
        let imageHash = rawImageHash.map { "\(Self.analysisCacheVersion):\($0)" }
        let reusableImageHash = pendingScanAllowsCacheReuse ? imageHash : nil
        let acceptedQualityWarningReasons = pendingAcceptedQualityWarningReasons
        let isUsingQualityOverride = !acceptedQualityWarningReasons.isEmpty

        if let reusableImageHash, let userId = currentSession?.localUserId {
            do {
                if let existing = try analysisRepository.analysis(byImageHash: reusableImageHash, userId: userId) {
                    let duplicatedAnalysisID = try persistCachedAnalysisAsFreshScan(
                        existing,
                        userId: userId,
                        imageHash: reusableImageHash,
                        imageData: imageData
                    )
                    try loadRecentAnalyses(for: userId)
                    await refreshReengagementNotifications()
                    pendingScanImageData = nil
                    pendingScanAllowsCacheReuse = false
                    clearScanError()
                    return duplicatedAnalysisID
                }
            } catch {
                // Cache lookup failure should not block a fresh analysis.
            }
        }

        do {
            let faceCount = try await faceDetectionService.detectFaceCount(in: imageData)
            if faceCount > 1 {
                setScanError(
                    "Use a photo with only your face in frame.",
                    reasons: [.multipleFaces]
                )
                return nil
            }

            let analysisID: String
            let result: OnDeviceAnalysisResult
            let debugMetadata: LocalAnalysisDebugMetadata?

            if isUsingQualityOverride {
                guard let qualityOverrideAnalysisService else {
                    setScanError("Could not continue with this lower-confidence scan right now. Please try another selfie.")
                    return nil
                }

                let overrideOutcome = try await qualityOverrideAnalysisService.analyze(
                    imageData: imageData,
                    imageHash: reusableImageHash,
                    userContext: currentSkinAnalysisUserContext(),
                    ignoredQualityReasons: acceptedQualityWarningReasons
                )

                analysisID = overrideOutcome.analysisID
                result = overrideOutcome.result
                debugMetadata = acceptedQualityOverrideDebugMetadata(
                    base: overrideOutcome.debugMetadata,
                    acceptedReasons: acceptedQualityWarningReasons
                )
            } else {
                let outcome = try await skinAnalysisService.analyze(
                    imageData: imageData,
                    imageHash: reusableImageHash,
                    userContext: currentSkinAnalysisUserContext()
                )
                analysisID = outcome.analysisID
                result = outcome.result
                debugMetadata = outcome.debugMetadata
            }

            persistAnalysis(
                id: analysisID,
                score: result.score,
                summary: result.summary,
                skinTypeDetected: result.skinTypeDetected,
                imageHash: imageHash,
                criteria: result.criteria,
                criterionInsights: result.criterionInsights,
                debugMetadata: debugMetadata
            )
            if cacheProcessedPhotoIfPossible(analysisID: analysisID, imageData: imageData),
               let userId = currentSession?.localUserId {
                try? loadRecentAnalyses(for: userId)
            }
            pendingScanImageData = nil
            pendingScanAllowsCacheReuse = false
            if isUsingQualityOverride {
                resetPendingScanQualityOverride()
            }
            clearScanError()
            await refreshReferralState(createInviteIfMissing: false)
            return analysisID
        } catch {
            if case let SkinAnalysisRemoteError.insufficientImageQuality(reasons) = error {
                setScanError(
                    "This selfie needs a cleaner capture before we can score it.",
                    reasons: reasons
                )
            } else if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                let reasons = parsedImageQualityReasons(from: localized)
                if reasons.isEmpty {
                    setScanError(localized)
                } else {
                    setScanError(
                        "This selfie needs a cleaner capture before we can score it.",
                        reasons: reasons
                    )
                }
            } else {
                setScanError("Could not analyze this image. Please try another selfie.")
            }
            pendingScanAllowsCacheReuse = false
            return nil
        }
    }

    public func refreshPaywallData() async {
        if let paywallRefreshTask {
            await paywallRefreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshBillingState()
            await self.loadPaywallPackages()
        }

        paywallRefreshTask = task
        await task.value
        paywallRefreshTask = nil
    }

    public func purchaseSubscription(_ packageId: String) async -> Bool {
        isPaywallLoading = true
        clearBillingError()
        defer { isPaywallLoading = false }

        do {
            let didPurchase = try await billingService.purchase(packageId)
            if didPurchase {
                await refreshBillingState()
            }
            return didPurchase && isProActive
        } catch {
            setBillingError(userFacingBillingError(from: error), origin: .checkout)
            return false
        }
    }

    public func restoreSubscriptions() async -> Bool {
        isPaywallLoading = true
        clearBillingError()
        defer { isPaywallLoading = false }

        do {
            let restored = try await billingService.restore()
            await refreshBillingState()
            return restored && isProActive
        } catch {
            setBillingError(userFacingBillingError(from: error), origin: .checkout)
            return false
        }
    }

    public func openAnalysisInHomeDeepDive(_ analysisId: String? = nil) {
        homeDeepDiveAnalysisId = analysisId
        shouldOpenHomeDeepDive = true
        presentAsRoot(.home)
    }

    public func recordReferralShareAttempt(activityType: UIActivity.ActivityType?) {
        guard canEarnReferralRewards else { return }
        guard isEligibleReferralActivity(activityType) else { return }
        do {
            referralShareCount = try settingsRepository.incrementReferralShareCount()
        } catch {
            referralErrorMessage = "Could not update your referral share count."
        }
    }

    private func setAuthenticatedState(with session: AuthSession) async {
        currentSession = session
        isAuthenticated = true
        clearScanError()
        synchronizeDebugAuthDiagnostics()
        loadCachedReferralState()

        if AppConfig.isDeveloperModeEnabled() && RESET_ONBOARDING_EACH_LAUNCH {
            try? onboardingRepository.resetOnboarding(userId: session.localUserId)
            try? onboardingDraftRepository.deleteDraft(userId: session.localUserId)
            clearOnboardingDraft()
            hasCompletedOnboarding = false
            try? loadRecentAnalyses(for: session.localUserId)
            try? loadSkinJourneyLogs(for: session.localUserId)
            presentAsRoot(.onboardingGender)
            await refreshPaywallData()
            await refreshReferralState(createInviteIfMissing: false)
            await refreshReengagementNotifications()
            await consumePendingNotificationIntentIfNeeded()
            if shouldAutoClaimPendingReferralCode {
                await claimPendingReferralCode(autoTriggered: true)
            }
            return
        }

        await synchronizeRemoteCacheIfNeeded(for: session)

        do {
            hasCompletedOnboarding = try onboardingRepository.hasCompletedOnboarding(userId: session.localUserId)
            if hasCompletedOnboarding {
                try onboardingDraftRepository.deleteDraft(userId: session.localUserId)
                clearOnboardingDraft()
                try loadRecentAnalyses(for: session.localUserId)
                try loadSkinJourneyLogs(for: session.localUserId)
                presentAsRoot(.home)
            } else {
                recentAnalyses = []
                analysisCalendarEntries = []
                totalScanCount = 0
                scanDayStreakCount = 0
                skinJourneyLogs = []
                try loadPersistedOnboardingDraft(for: session.localUserId)
                let resumeRoute = try onboardingDraftRepository.nextRoute(userId: session.localUserId) ?? .onboardingGender
                presentAsRoot(resumeRoute)
            }
        } catch {
            hasCompletedOnboarding = false
            recentAnalyses = []
            analysisCalendarEntries = []
            totalScanCount = 0
            scanDayStreakCount = 0
            skinJourneyLogs = []
            try? loadPersistedOnboardingDraft(for: session.localUserId)
            let resumeRoute = (try? onboardingDraftRepository.nextRoute(userId: session.localUserId)) ?? .onboardingGender
            presentAsRoot(resumeRoute)
        }

        await refreshPaywallData()
        await refreshReferralState(createInviteIfMissing: true)
        await refreshReengagementNotifications()
        await consumePendingNotificationIntentIfNeeded()
        if shouldAutoClaimPendingReferralCode && hasCompletedOnboarding {
            await claimPendingReferralCode(autoTriggered: true)
        }
    }

    private func shouldUseRemoteBackend(for session: AuthSession?) -> Bool {
        guard let session else { return false }
        return session.provider != .guest &&
            session.usesRemoteBackend &&
            remoteOnboardingRepository != nil &&
            remoteScanRepository != nil &&
            remoteJourneyRepository != nil
    }

    private func synchronizeRemoteCacheIfNeeded(for session: AuthSession) async {
        guard shouldUseRemoteBackend(for: session) else { return }

        do {
            try await synchronizeRemoteOnboardingIfNeeded(for: session)
            try await synchronizeRemoteAnalysesIfNeededInternal(for: session)
            try await synchronizeRemoteJourneyIfNeededInternal(for: session)
            clearHomeError(for: .cloudSync)
        } catch {
            setHomeError("Could not sync your cloud data.", context: .cloudSync)
        }
    }

    private func synchronizeRemoteOnboardingIfNeeded(for session: AuthSession) async throws {
        guard let remoteOnboardingRepository else { return }

        let remoteProfile = try await remoteOnboardingRepository.fetchProfile()
        if let remoteProfile {
            try onboardingRepository.saveOnboarding(
                userId: session.localUserId,
                skinTypes: remoteProfile.skinTypes,
                goal: remoteProfile.goal,
                routine: remoteProfile.routineLevel
            )
            return
        }

        if let localProfile = try onboardingRepository.profile(userId: session.localUserId) {
            try await remoteOnboardingRepository.saveProfile(
                skinTypes: decodedSkinTypesCSV(localProfile.skinTypesCSV),
                goal: localProfile.goal,
                routineLevel: localProfile.routine
            )
        }
    }

    private func synchronizeRemoteAnalysesIfNeeded() async {
        guard let session = currentSession, shouldUseRemoteBackend(for: session) else { return }
        do {
            try await synchronizeRemoteAnalysesIfNeededInternal(for: session)
            try loadRecentAnalyses(for: session.localUserId)
            clearHomeError(for: .recentAnalysesSync)
        } catch {
            setHomeError("Could not sync recent analyses.", context: .recentAnalysesSync)
        }
    }

    private func synchronizeRemoteAnalysesIfNeededInternal(for session: AuthSession) async throws {
        guard let remoteScanRepository else { return }

        var remoteScans = try await remoteScanRepository.fetchRecentAnalyses()
        if remoteScans.isEmpty {
            let localAnalyses = try analysisRepository.fetchRecentAnalyses(userId: session.localUserId, limit: 500)
            try await remoteScanRepository.importLocalAnalyses(localAnalyses)
            remoteScans = try await remoteScanRepository.fetchRecentAnalyses()
        }

        for scan in remoteScans {
            try saveAnalysisCache(
                id: scan.id,
                userId: session.localUserId,
                score: scan.score,
                summary: scan.summary,
                skinTypeDetected: scan.skinTypeDetected,
                imageHash: nil,
                criteria: scan.criteria,
                criterionInsights: scan.criterionInsights,
                debugMetadata: scan.debugMetadata(source: .remoteSynced),
                createdAt: scan.createdAt
            )
        }
    }

    private func synchronizeRemoteJourneyIfNeeded() async {
        guard let session = currentSession, shouldUseRemoteBackend(for: session) else { return }
        do {
            try await synchronizeRemoteJourneyIfNeededInternal(for: session)
            try loadSkinJourneyLogs(for: session.localUserId)
            clearHomeError(for: .skinJourneySync)
        } catch {
            setHomeError("Could not sync your skin journey.", context: .skinJourneySync)
        }
    }

    private func synchronizeRemoteJourneyIfNeededInternal(for session: AuthSession) async throws {
        guard let remoteJourneyRepository else { return }

        var remoteLogs = try await remoteJourneyRepository.fetchLogs()
        if remoteLogs.isEmpty {
            let localLogs = try skinJourneyRepository.fetchLogs(userId: session.localUserId)
            try await remoteJourneyRepository.importLocalLogs(localLogs)
            remoteLogs = try await remoteJourneyRepository.fetchLogs()
        }

        for log in remoteLogs {
            try skinJourneyRepository.upsertLog(
                userId: session.localUserId,
                date: log.dayStartAt,
                routineStepIDs: log.routineStepIDs,
                treatmentIDs: log.treatmentIDs,
                skinStatusIDs: log.skinStatusIDs,
                note: log.note
            )
        }
    }

    private func loadRecentAnalyses(for userId: String) throws {
        let allAnalyses = try analysisRepository.fetchAllAnalyses(userId: userId)
        recentAnalyses = Array(allAnalyses.prefix(20))
        analysisCalendarEntries = Self.makeAnalysisCalendarEntries(from: allAnalyses)
        totalScanCount = allAnalyses.count
        scanDayStreakCount = AnalysisRepository.consecutiveScanDayStreak(
            forDescendingScanDates: allAnalyses.map(\.createdAt)
        )
    }

    private func loadSkinJourneyLogs(for userId: String) throws {
        skinJourneyLogs = try skinJourneyRepository.fetchLogs(userId: userId)
    }

    private static func makeAnalysisCalendarEntries(
        from analyses: [LocalAnalysis],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AnalysisCalendarEntry] {
        var entriesByDay: [Date: AnalysisCalendarEntry] = [:]

        for analysis in analyses {
            let dayStartAt = calendar.startOfDay(for: analysis.createdAt)
            guard entriesByDay[dayStartAt] == nil else { continue }
            entriesByDay[dayStartAt] = AnalysisCalendarEntry(
                analysisID: analysis.id,
                dayStartAt: dayStartAt,
                createdAt: analysis.createdAt,
                score: analysis.score,
                localImageRelativePath: analysis.localImageRelativePath,
                debugMetadata: analysis.debugMetadata
            )
        }

        return entriesByDay.values.sorted { left, right in
            if left.dayStartAt == right.dayStartAt {
                return left.createdAt > right.createdAt
            }
            return left.dayStartAt > right.dayStartAt
        }
    }

    private func loadPaywallPackages() async {
        isPaywallPackagesLoading = true
        defer { isPaywallPackagesLoading = false }

        do {
            paywallPackages = try await billingService.fetchPackages()
            clearBillingError(for: .packages)
        } catch {
            setBillingError(userFacingBillingError(from: error), origin: .packages)
        }
    }

    private func refreshBillingState() async {
        do {
            let entitlement = try await billingService.currentEntitlement()
            applyBillingEntitlement(entitlement)
            hasResolvedBillingState = true
        } catch {
#if DEBUG
            if FORCE_DEBUG_PRO_ACCESS {
                isProActive = true
                subscriptionPlanId = DEBUG_PRO_PLAN_ID
                subscriptionExpiry = nil
                hasResolvedBillingState = true
                clearBillingError(for: .entitlement)
                return
            }
#endif
            if hasResolvedBillingState {
                setBillingError(userFacingBillingError(from: error), origin: .entitlement)
                return
            }
            isProActive = false
            subscriptionPlanId = nil
            subscriptionExpiry = nil
            setBillingError(userFacingBillingError(from: error), origin: .entitlement)
        }
    }

    private func applyBillingEntitlement(_ entitlement: SubscriptionEntitlement) {
#if DEBUG
        if FORCE_DEBUG_PRO_ACCESS {
            isProActive = true
            subscriptionPlanId = entitlement.productId ?? DEBUG_PRO_PLAN_ID
            subscriptionExpiry = entitlement.expirationDate
            clearBillingError(for: .entitlement)
            return
        }
#endif

        isProActive = entitlement.isActive
        subscriptionPlanId = entitlement.productId
        subscriptionExpiry = entitlement.expirationDate
        clearBillingError(for: .entitlement)
    }

    private func loadStoredNotificationPromptState() {
        notificationPromptState = (try? settingsRepository.notificationPromptState()) ?? .neverAsked
    }

    private func loadPersistedLaunchSettings() {
        hasAcceptedCurrentScanConsent = (try? settingsRepository.hasAcceptedScanConsent(version: AppConfig.scanConsentVersion)) ?? false
        scanConsentAcceptedAt = try? settingsRepository.scanConsentAcceptedAt()
        if AppConfig.isReferralsEnabled() {
            pendingReferralCode = try? settingsRepository.pendingReferralCode()
            loadCachedReferralState()
        } else {
            clearPersistedReferralStateIfDisabled()
        }
    }

    private func loadCachedReferralState() {
        guard let cachedState = try? settingsRepository.referralState() else {
            referralShareCount = 0
            validatedReferralCount = 0
            referralRewardCount = 0
            claimedReferralCode = nil
            referralInviteCode = nil
            referralInviteURLString = nil
            return
        }

        referralShareCount = cachedState.shareCount
        validatedReferralCount = cachedState.validatedReferralCount
        referralRewardCount = cachedState.rewardCount
        claimedReferralCode = cachedState.claimedCode
        referralInviteCode = cachedState.inviteCode
        referralInviteURLString = cachedState.inviteURLString
        if pendingReferralCode == nil {
            pendingReferralCode = cachedState.pendingCode
        }
    }

    private func clearPersistedReferralStateIfDisabled() {
        try? settingsRepository.clearCachedReferralStatus()
        pendingReferralCode = nil
        referralShareCount = 0
        validatedReferralCount = 0
        referralRewardCount = 0
        claimedReferralCode = nil
        referralInviteCode = nil
        referralInviteURLString = nil
        referralErrorMessage = nil
        referralSuccessMessage = nil
        isReferralLoading = false
        shouldAutoClaimPendingReferralCode = false
    }

    @discardableResult
    private func synchronizeNotificationAuthorizationStatus() async -> NotificationAuthorizationStatus {
        let authorizationStatus = await notificationService.refreshAuthorizationStatus()

        do {
            try settingsRepository.setNotificationAuthorizationStatus(authorizationStatus)

            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                try settingsRepository.setNotificationPromptState(.authorized)
                notificationPromptState = .authorized
            case .denied:
                try settingsRepository.setNotificationPromptState(.systemDenied)
                notificationPromptState = .systemDenied
            case .notDetermined:
                notificationPromptState = try settingsRepository.notificationPromptState()
            }
        } catch {
            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationPromptState = .authorized
            case .denied:
                notificationPromptState = .systemDenied
            case .notDetermined:
                break
            }
        }

        return authorizationStatus
    }

    private func persistOnboardingDraft(lastCompletedStep: OnboardingDraftStep) {
        guard let userId = currentSession?.localUserId else { return }

        do {
            try onboardingDraftRepository.saveDraft(
                userId: userId,
                gender: onboardingDraftGender,
                skinTypes: onboardingDraftSkinTypes.sorted(),
                goal: onboardingDraftGoal,
                routine: onboardingDraftRoutine,
                lastCompletedStep: lastCompletedStep
            )
        } catch {
            authErrorMessage = "Could not save onboarding progress locally."
        }

        Task {
            await refreshReengagementNotifications()
        }
    }

    private func loadPersistedOnboardingDraft(for userId: String) throws {
        guard let draft = try onboardingDraftRepository.draft(userId: userId) else {
            clearOnboardingDraft()
            return
        }

        onboardingDraftGender = draft.gender
        onboardingDraftSkinTypes = Set(onboardingDraftRepository.skinTypes(for: draft))
        onboardingDraftGoal = draft.goal
        onboardingDraftRoutine = draft.routine
    }

    private func currentSkinAnalysisUserContext() -> SkinAnalysisUserContext? {
        if let session = currentSession, let profile = try? onboardingRepository.profile(userId: session.localUserId) {
            return SkinAnalysisUserContext(
                skinTypes: decodedSkinTypesCSV(profile.skinTypesCSV),
                goal: profile.goal,
                routineLevel: profile.routine
            )
        }

        let fallback = SkinAnalysisUserContext(
            skinTypes: onboardingDraftSkinTypes.sorted(),
            goal: onboardingDraftGoal,
            routineLevel: onboardingDraftRoutine
        )
        return fallback.isEmpty ? nil : fallback
    }

    private func decodedSkinTypesCSV(_ value: String) -> [String] {
        value
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func weightedReferenceScore(from neighbors: [SimilarAnalysisNeighbor]) -> Double {
        var weightedTotal = 0.0
        var totalWeight = 0.0

        for neighbor in neighbors {
            let weight = 1 / max(neighbor.distance, 0.12)
            weightedTotal += neighbor.score * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return neighbors.last?.score ?? 0 }
        return weightedTotal / totalWeight
    }

    private static func criteriaDistance(between lhs: [String: Double], and rhs: [String: Double]) -> Double {
        let keys = ["Hydration", "Texture", "Uniformity", "Luminosity"]
        let distances = keys.compactMap { key -> Double? in
            guard let left = lhs[key], let right = rhs[key] else { return nil }
            return abs(left - right)
        }

        guard !distances.isEmpty else { return .greatestFiniteMagnitude }
        return distances.reduce(0, +) / Double(distances.count)
    }

    private static func daysBetween(_ lhs: Date, _ rhs: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: lhs), to: calendar.startOfDay(for: rhs)).day ?? 0)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func scoreClamped(_ score: Double) -> Double {
        Self.clamp(score, min: 0, max: 10)
    }

    private func encodeCriterionInsights(_ criterionInsights: [String: SkinCriterionInsight]?) throws -> String? {
        guard let criterionInsights else { return nil }
        let data = try JSONEncoder().encode(criterionInsights)
        return String(data: data, encoding: .utf8)
    }

    private func encodeDebugMetadata(_ debugMetadata: LocalAnalysisDebugMetadata?) throws -> String? {
        guard let debugMetadata else { return nil }
        let data = try JSONEncoder().encode(debugMetadata)
        return String(data: data, encoding: .utf8)
    }

    private func localCacheDebugMetadata(from analysis: LocalAnalysis) -> LocalAnalysisDebugMetadata {
        if let existing = analysis.debugMetadata {
            return existing.with(source: .localCache)
        }

        return LocalAnalysisDebugMetadata(
            analysisVersion: nil,
            predictedBand: predictedBand(for: analysis.score),
            observedConditions: nil,
            imageQualityStatus: nil,
            imageQualityReasons: [],
            referenceCatalogVersion: nil,
            finalScore: analysis.score,
            model: nil,
            source: .localCache
        )
    }

    private func predictedBand(for score: Double) -> String {
        switch score {
        case ..<2.0:
            return "0-2"
        case ..<4.0:
            return "2-4"
        case ..<6.0:
            return "4-6"
        case ..<8.0:
            return "6-8"
        default:
            return "8-10"
        }
    }

    private func buildReengagementContext() -> ReengagementContext? {
        guard let session = currentSession else { return nil }

        let profile = try? onboardingRepository.profile(userId: session.localUserId)
        let resumeRoute = hasCompletedOnboarding
            ? nil
            : (try? onboardingDraftRepository.nextRoute(userId: session.localUserId))

        return ReengagementContext(
            userId: session.localUserId,
            goal: hasCompletedOnboarding ? profile?.goal ?? onboardingDraftGoal : onboardingDraftGoal,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAnyScan: !recentAnalyses.isEmpty,
            lastActiveAt: (try? settingsRepository.lastActiveAt()) ?? .now,
            resumeRoute: resumeRoute,
            latestScanDate: recentAnalyses.first?.createdAt
        )
    }

    private func refreshReengagementNotifications() async {
        guard let context = buildReengagementContext() else {
            await notificationService.cancelReengagementNotifications()
            return
        }

        await notificationService.rescheduleReengagementNotifications(context: context)
    }

    private func consumePendingNotificationIntentIfNeeded() async {
        guard let pendingIntent = notificationService.consumePendingOpenIntent() else { return }

        switch pendingIntent {
        case .resumeOnboarding:
            guard let session = currentSession, !hasCompletedOnboarding else { return }
            let resumeRoute = (try? onboardingDraftRepository.nextRoute(userId: session.localUserId)) ?? .onboardingGender
            presentAsRoot(resumeRoute)
        case .openFirstScan:
            guard isAuthenticated, hasCompletedOnboarding else { return }
            presentAsRoot(.home)
            openUploadFlow()
        case .openHome:
            guard isAuthenticated else { return }
            presentAsRoot(.home)
        }
    }

    private func clearOnboardingDraft() {
        onboardingDraftGender = nil
        onboardingDraftSkinTypes = []
        onboardingDraftGoal = nil
        onboardingDraftRoutine = nil
    }

    private func refreshReferralState(createInviteIfMissing: Bool) async {
        guard shouldUseRemoteBackend(for: currentSession), let remoteReferralRepository else { return }
        guard canEarnReferralRewards else { return }

        do {
            var status = try await remoteReferralRepository.fetchStatus()
            if createInviteIfMissing && (status.inviteCode == nil || status.inviteURL == nil) {
                status = try await remoteReferralRepository.createInvite()
            }
            try settingsRepository.saveReferralStatus(status)
            applyReferralStatus(status, preservePendingCode: true)
        } catch {
            if referralInviteCode == nil {
                referralErrorMessage = nil
            }
        }
    }

    private func applyReferralStatus(_ status: RemoteReferralStatus, preservePendingCode: Bool) {
        validatedReferralCount = status.validatedReferralCount
        referralRewardCount = status.rewardCount
        claimedReferralCode = status.claimedCode
        referralInviteCode = status.inviteCode
        referralInviteURLString = status.inviteURLString

        if !preservePendingCode {
            pendingReferralCode = nil
        }
    }

    private func claimPendingReferralCode(autoTriggered: Bool) async {
        guard let normalizedCode = AppConfig.normalizedReferralCode(pendingReferralCode) else {
            if !autoTriggered {
                referralErrorMessage = "Enter a valid referral code before claiming it."
            }
            return
        }

        guard AppConfig.isReferralsEnabled() else {
            if !autoTriggered {
                referralErrorMessage = "Referral claims are unavailable right now."
            }
            return
        }

        guard canEarnReferralRewards else {
            if !autoTriggered {
                referralErrorMessage = "Activate cloud beta with Apple or Google before claiming referral codes."
            }
            return
        }

        guard hasCompletedOnboarding else {
            if !autoTriggered {
                referralErrorMessage = "Finish onboarding before claiming a referral code."
            }
            return
        }

        guard shouldUseRemoteBackend(for: currentSession), let remoteReferralRepository else {
            if !autoTriggered {
                referralErrorMessage = "Referral claims are unavailable right now."
            }
            return
        }

        isReferralLoading = true
        referralErrorMessage = nil
        if !autoTriggered {
            referralSuccessMessage = nil
        }
        defer { isReferralLoading = false }

        do {
            let response = try await remoteReferralRepository.claimReferralCode(normalizedCode)
            try settingsRepository.saveReferralStatus(response.referral)
            try settingsRepository.setPendingReferralCode(nil)
            applyReferralStatus(response.referral, preservePendingCode: false)
            shouldAutoClaimPendingReferralCode = false
            let message = referralMessage(
                for: response.status,
                backendMessage: response.message,
                code: normalizedCode
            )
            switch response.status {
            case .selfReferral, .duplicate:
                referralSuccessMessage = nil
                referralErrorMessage = message
            case .claimed, .alreadyClaimed, .pendingValidation:
                referralSuccessMessage = message
            }
        } catch {
            let message = userFacingError(from: error)
            if autoTriggered {
                referralSuccessMessage = nil
            }
            referralErrorMessage = message.isEmpty ? "Could not claim that referral code right now." : message
        }
    }

    private func referralMessage(
        for status: RemoteReferralClaimResult,
        backendMessage: String?,
        code: String
    ) -> String {
        if let backendMessage, !backendMessage.isEmpty {
            return backendMessage
        }

        switch status {
        case .claimed:
            return "Referral code \(code) was claimed. Finish your first scan to validate it."
        case .alreadyClaimed:
            return "This account already has a referral claim on file."
        case .pendingValidation:
            return "Referral code \(code) is on file and waiting for your first scan."
        case .selfReferral:
            return "You cannot use your own referral code."
        case .duplicate:
            return "That referral code was already used on this account."
        }
    }

    private func referralCaptureMessage(for code: String) -> String {
        if isGuestSession || currentSession == nil {
            return "Invite code \(code) was saved. Sign in with Apple or Google when you are ready to claim it."
        }

        if !hasCompletedOnboarding {
            return "Invite code \(code) was saved. Finish onboarding to claim it."
        }

        return "Invite code \(code) is ready to claim."
    }

    private func isEligibleReferralActivity(_ activityType: UIActivity.ActivityType?) -> Bool {
        guard let activityType else { return false }

        let blockedActivityTypes: Set<String> = [
            UIActivity.ActivityType.copyToPasteboard.rawValue,
            UIActivity.ActivityType.airDrop.rawValue,
            UIActivity.ActivityType.assignToContact.rawValue,
            UIActivity.ActivityType.addToReadingList.rawValue,
            UIActivity.ActivityType.openInIBooks.rawValue,
            UIActivity.ActivityType.print.rawValue,
            UIActivity.ActivityType.saveToCameraRoll.rawValue,
            UIActivity.ActivityType.markupAsPDF.rawValue
        ]

        return !blockedActivityTypes.contains(activityType.rawValue)
    }

    private func resetSessionStateToSignedOut() {
        currentSession = nil
        isAuthenticated = false
        hasCompletedOnboarding = false
        shouldOpenHomeDeepDive = false
        homeDeepDiveAnalysisId = nil
        pendingScanImageData = nil
        resetPendingScanQualityOverride()
        clearScanError()
        clearOnboardingDraft()
        recentAnalyses = []
        analysisCalendarEntries = []
        totalScanCount = 0
        scanDayStreakCount = 0
        skinJourneyLogs = []
        pendingReferralCode = nil
        referralShareCount = 0
        validatedReferralCount = 0
        referralRewardCount = 0
        claimedReferralCode = nil
        referralInviteCode = nil
        referralInviteURLString = nil
        referralErrorMessage = nil
        referralSuccessMessage = nil
        isReferralLoading = false
        shouldAutoClaimPendingReferralCode = false
        clearHomeErrorMessage()
        paywallRefreshTask?.cancel()
        paywallRefreshTask = nil
        billingErrorOrigin = nil
        hasResolvedBillingState = false
        isProActive = false
        subscriptionPlanId = nil
        subscriptionExpiry = nil
        paywallPackages = []
        isPaywallPackagesLoading = false
        billingErrorMessage = nil
        synchronizeDebugAuthDiagnostics()
    }

    private func transitionToGuestSession() async {
        authErrorMessage = nil

        do {
            let guestSession = try await authService.continueAsGuest()
            await setAuthenticatedState(with: guestSession)
        } catch {
            authErrorMessage = userFacingError(from: error)
            presentAsRoot(.auth)
        }
    }

    private func synchronizeDebugAuthDiagnostics() {
        debugHasStoredBackendSession = authService.hasStoredBackendSession
        debugGuestBackendSessionError = authService.lastGuestBackendSessionErrorDescription
    }

    private func setScanError(_ message: String, reasons: [SkinImageQualityReason] = []) {
        scanErrorMessage = message
        scanErrorReasons = reasons
    }

    private func setHomeError(_ message: String, context: HomeErrorContext) {
        homeErrorMessage = message
        homeErrorContext = context
    }

    private func clearHomeError(for context: HomeErrorContext) {
        guard homeErrorContext == context else { return }
        clearHomeErrorMessage()
    }

    private func clearScanError() {
        scanErrorMessage = nil
        scanErrorReasons = []
    }

    private func setBillingError(_ message: String, origin: BillingErrorOrigin) {
        billingErrorMessage = message
        billingErrorOrigin = origin
    }

    private func clearBillingError(for origin: BillingErrorOrigin? = nil) {
        guard let origin else {
            billingErrorMessage = nil
            billingErrorOrigin = nil
            return
        }

        guard billingErrorOrigin == origin else { return }
        billingErrorMessage = nil
        billingErrorOrigin = nil
    }

    private func userFacingError(from error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        return error.localizedDescription
    }

    private func userFacingBillingError(from error: Error) -> String {
        if let billingError = error as? BillingError {
            return billingError.localizedDescription
        }
        return error.localizedDescription
    }
}
