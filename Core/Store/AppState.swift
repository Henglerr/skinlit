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

#if DEBUG
private let RESET_ONBOARDING_EACH_LAUNCH = false
#endif

@MainActor
public class AppState: ObservableObject {
    private static let analysisCacheVersion = "2026-02-24-proxy-v1"
    private let authService: AuthService
    private let onboardingDraftRepository: OnboardingDraftRepository
    private let onboardingRepository: OnboardingRepository
    private let analysisRepository: AnalysisRepository
    private let skinJourneyRepository: SkinJourneyRepository
    private let settingsRepository: SettingsRepository
    private let notificationService: NotificationService
    private let billingService: BillingService
    private let skinAnalysisService: SkinAnalysisService
    private let faceDetectionService: FaceDetectionService
    private var pendingScanImageData: Data?

    @Published public var currentRoute: [AppRoute] = []
    @Published public var isAuthenticated: Bool = false
    @Published public var hasCompletedOnboarding: Bool = false
    @AppStorage("appTheme") public var appTheme: String = "pastel"
    @AppStorage("installConsumedFreeScans") public var installConsumedFreeScans: Int = 0
    @AppStorage("didMigrateInstallConsumedFreeScans") private var didMigrateInstallConsumedFreeScans: Bool = false
    @AppStorage("referralShareCount") public var referralShareCount: Int = 0
    @AppStorage("validatedReferralCount") public var validatedReferralCount: Int = 0
    @Published public var isBootstrapping: Bool = true
    @Published public var isAuthLoading: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var scanErrorMessage: String? = nil
    @Published public var shouldOpenHomeDeepDive: Bool = false
    @Published public var homeDeepDiveAnalysisId: String? = nil
    @Published public var currentSession: AuthSession? = nil
    @Published public var isGoogleConfigured: Bool = false
    @Published public var onboardingDraftGender: String? = nil
    @Published public var onboardingDraftSkinTypes: Set<String> = []
    @Published public var onboardingDraftGoal: String? = nil
    @Published public var onboardingDraftRoutine: String? = nil
    @Published public var recentAnalyses: [LocalAnalysis] = []
    @Published public var skinJourneyLogs: [SkinJourneyLog] = []
    @Published public var notificationPromptState: NotificationPromptState = .neverAsked

    @Published public var isProActive: Bool = false
    @Published public var subscriptionPlanId: String? = nil
    @Published public var subscriptionExpiry: Date? = nil
    @Published public var paywallPackages: [PaywallPackage] = []
    @Published public var isPaywallLoading: Bool = false
    @Published public var billingErrorMessage: String? = nil

    public static let freeScanQuota = 2

    public var referralBonusScansEarned: Int {
        validatedReferralCount / 2
    }

    public var totalFreeScanAllowance: Int {
        Self.freeScanQuota + referralBonusScansEarned
    }

    public var validatedReferralsUntilNextFreeScan: Int {
        let progress = validatedReferralCount % 2
        return progress == 0 ? 2 : 1
    }

    public var remainingFreeScans: Int {
        max(0, totalFreeScanAllowance - installConsumedFreeScans)
    }

    public var canRunScan: Bool {
        isProActive || installConsumedFreeScans < totalFreeScanAllowance
    }

    public var canEarnReferralRewards: Bool {
        guard let session = currentSession else { return false }
        return session.provider != .guest
    }

    public init(
        authService: AuthService,
        onboardingDraftRepository: OnboardingDraftRepository,
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        skinJourneyRepository: SkinJourneyRepository,
        settingsRepository: SettingsRepository,
        notificationService: NotificationService,
        billingService: BillingService,
        skinAnalysisService: SkinAnalysisService,
        faceDetectionService: FaceDetectionService
    ) {
        self.authService = authService
        self.onboardingDraftRepository = onboardingDraftRepository
        self.onboardingRepository = onboardingRepository
        self.analysisRepository = analysisRepository
        self.skinJourneyRepository = skinJourneyRepository
        self.settingsRepository = settingsRepository
        self.notificationService = notificationService
        self.billingService = billingService
        self.skinAnalysisService = skinAnalysisService
        self.faceDetectionService = faceDetectionService
        self.isGoogleConfigured = authService.isGoogleSignInAvailable
    }

    public func navigate(to route: AppRoute) {
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

        hydrateInstallFreeScanUsageIfNeeded()
        loadStoredNotificationPromptState()

        let restoredSession = await authService.restoreSession()
        guard let restoredSession else {
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
        resetSessionStateToSignedOut()
        presentAsRoot(.auth)
    }

    public func deleteAccount() async {
        do {
            try await authService.deleteAccount()
            await notificationService.cancelReengagementNotifications()
            _ = notificationService.consumePendingOpenIntent()
            resetSessionStateToSignedOut()
            presentAsRoot(.auth)
        } catch {
            authErrorMessage = userFacingError(from: error)
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
            try onboardingDraftRepository.deleteDraft(userId: session.localUserId)
            hasCompletedOnboarding = true
            clearOnboardingDraft()
            try loadRecentAnalyses(for: session.localUserId)
            try loadSkinJourneyLogs(for: session.localUserId)
            presentAsRoot(.home)
            await refreshPaywallData()
            await refreshReengagementNotifications()
        } catch {
            authErrorMessage = "Could not save onboarding preferences locally."
        }
    }

    public func persistAnalysis(
        id: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String? = nil,
        criteria: [String: Double]
    ) {
        guard let userId = currentSession?.localUserId else { return }
        do {
            let criteriaData = try JSONEncoder().encode(criteria)
            let criteriaJSON = String(data: criteriaData, encoding: .utf8) ?? "{}"
            try analysisRepository.saveAnalysis(
                id: id,
                userId: userId,
                score: score,
                summary: summary,
                skinTypeDetected: skinTypeDetected,
                imageHash: imageHash,
                criteriaJSON: criteriaJSON
            )
            if !isProActive {
                installConsumedFreeScans += 1
            }
            try loadRecentAnalyses(for: userId)
            Task {
                await refreshReengagementNotifications()
            }
        } catch {
            authErrorMessage = "Could not save this analysis."
        }
    }

    public func refreshRecentAnalyses() {
        guard let userId = currentSession?.localUserId else {
            recentAnalyses = []
            return
        }

        do {
            try loadRecentAnalyses(for: userId)
        } catch {
            authErrorMessage = "Could not load recent analyses."
        }
    }

    public func refreshSkinJourneyLogs() {
        guard let userId = currentSession?.localUserId else {
            skinJourneyLogs = []
            return
        }

        do {
            try loadSkinJourneyLogs(for: userId)
        } catch {
            authErrorMessage = "Could not load your skin journey."
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
        } catch {
            authErrorMessage = "Could not save your skin journey."
        }
    }

    public func deleteSkinJourneyLog(date: Date) {
        guard let userId = currentSession?.localUserId else { return }

        do {
            try skinJourneyRepository.deleteLog(userId: userId, date: date)
            try loadSkinJourneyLogs(for: userId)
        } catch {
            authErrorMessage = "Could not delete this skin journey log."
        }
    }

    public func skinJourneyLog(on date: Date) -> SkinJourneyLog? {
        let calendar = Calendar.autoupdatingCurrent
        return skinJourneyLogs.first { calendar.isDate($0.dayStartAt, inSameDayAs: date) }
    }

    public func queueScanImageData(_ imageData: Data) {
        pendingScanImageData = imageData
        scanErrorMessage = nil
    }

    public func processPendingAnalysis() async -> String? {
        guard currentSession?.localUserId != nil else {
            scanErrorMessage = "Please sign in before running a scan."
            return nil
        }

        guard canRunScan else {
            scanErrorMessage = "Your free scans are finished. Upgrade to PRO to keep scanning."
            return nil
        }

        guard let imageData = pendingScanImageData else {
            scanErrorMessage = "Select a selfie before starting analysis."
            return nil
        }

        pendingScanImageData = nil
        let rawImageHash = ImageFingerprint.stableHash(for: imageData)
        let imageHash = rawImageHash.map { "\(Self.analysisCacheVersion):\($0)" }

        if let imageHash, let userId = currentSession?.localUserId {
            do {
                if let existing = try analysisRepository.analysis(byImageHash: imageHash, userId: userId) {
                    try analysisRepository.touchAnalysis(id: existing.id)
                    try loadRecentAnalyses(for: userId)
                    await refreshReengagementNotifications()
                    scanErrorMessage = nil
                    return existing.id
                }
            } catch {
                // Cache lookup failure should not block a fresh analysis.
            }
        }

        do {
            let faceCount = try await faceDetectionService.detectFaceCount(in: imageData)
            if faceCount > 1 {
                scanErrorMessage = "Multiple faces detected. Use a photo with only your face."
                return nil
            }

            let result = try await skinAnalysisService.analyze(imageData: imageData)
            let analysisId = UUID().uuidString
            persistAnalysis(
                id: analysisId,
                score: result.score,
                summary: result.summary,
                skinTypeDetected: result.skinTypeDetected,
                imageHash: imageHash,
                criteria: result.criteria
            )
            return analysisId
        } catch {
            if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                scanErrorMessage = localized
            } else {
                scanErrorMessage = "Could not analyze this image. Please try another selfie."
            }
            return nil
        }
    }

    public func refreshPaywallData() async {
        await refreshBillingState()
        await loadPaywallPackages()
    }

    public func purchaseSubscription(_ packageId: String) async -> Bool {
        isPaywallLoading = true
        billingErrorMessage = nil
        defer { isPaywallLoading = false }

        do {
            let didPurchase = try await billingService.purchase(packageId)
            if didPurchase {
                await refreshBillingState()
            }
            return didPurchase && isProActive
        } catch {
            billingErrorMessage = userFacingBillingError(from: error)
            return false
        }
    }

    public func restoreSubscriptions() async -> Bool {
        isPaywallLoading = true
        billingErrorMessage = nil
        defer { isPaywallLoading = false }

        do {
            let restored = try await billingService.restore()
            await refreshBillingState()
            return restored && isProActive
        } catch {
            billingErrorMessage = userFacingBillingError(from: error)
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
        referralShareCount += 1
    }

    public func recordValidatedReferral(count: Int = 1) {
        guard count > 0 else { return }
        validatedReferralCount += count
    }

    private func setAuthenticatedState(with session: AuthSession) async {
        currentSession = session
        isAuthenticated = true
        scanErrorMessage = nil

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
                skinJourneyLogs = []
                try loadPersistedOnboardingDraft(for: session.localUserId)
                let resumeRoute = try onboardingDraftRepository.nextRoute(userId: session.localUserId) ?? .onboardingGender
                presentAsRoot(resumeRoute)
            }
        } catch {
            hasCompletedOnboarding = false
            recentAnalyses = []
            skinJourneyLogs = []
            try? loadPersistedOnboardingDraft(for: session.localUserId)
            let resumeRoute = (try? onboardingDraftRepository.nextRoute(userId: session.localUserId)) ?? .onboardingGender
            presentAsRoot(resumeRoute)
        }

        await refreshPaywallData()
        await refreshReengagementNotifications()
        await consumePendingNotificationIntentIfNeeded()
    }

    private func loadRecentAnalyses(for userId: String) throws {
        recentAnalyses = try analysisRepository.fetchRecentAnalyses(userId: userId, limit: 20)
    }

    private func loadSkinJourneyLogs(for userId: String) throws {
        skinJourneyLogs = try skinJourneyRepository.fetchLogs(userId: userId)
    }

    private func loadPaywallPackages() async {
        do {
            paywallPackages = try await billingService.fetchPackages()
        } catch {
            paywallPackages = []
            billingErrorMessage = userFacingBillingError(from: error)
        }
    }

    private func refreshBillingState() async {
        do {
            let entitlement = try await billingService.currentEntitlement()
            isProActive = entitlement.isActive
            subscriptionPlanId = entitlement.productId
            subscriptionExpiry = entitlement.expirationDate
        } catch {
            isProActive = false
            subscriptionPlanId = nil
            subscriptionExpiry = nil
            billingErrorMessage = userFacingBillingError(from: error)
        }
    }

    private func hydrateInstallFreeScanUsageIfNeeded() {
        guard !didMigrateInstallConsumedFreeScans else { return }

        let migratedUsage: Int
        do {
            migratedUsage = min(Self.freeScanQuota, try analysisRepository.totalAnalysisCount())
        } catch {
            migratedUsage = installConsumedFreeScans
        }

        installConsumedFreeScans = max(installConsumedFreeScans, migratedUsage)
        didMigrateInstallConsumedFreeScans = true
    }

    private func loadStoredNotificationPromptState() {
        notificationPromptState = (try? settingsRepository.notificationPromptState()) ?? .neverAsked
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
            navigate(to: .upload)
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
        scanErrorMessage = nil
        clearOnboardingDraft()
        recentAnalyses = []
        skinJourneyLogs = []
        isProActive = false
        subscriptionPlanId = nil
        subscriptionExpiry = nil
        paywallPackages = []
        billingErrorMessage = nil
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
