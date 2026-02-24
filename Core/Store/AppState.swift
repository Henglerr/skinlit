import Foundation
import Combine
import SwiftUI
import AuthenticationServices
import UIKit
import CryptoKit

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
    case scanPrep(useCamera: Bool)  // pre-scan checklist + face processing
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

// ─────────────────────────────────────────────────────────────────────────────
// 🧪 ONBOARDING TESTING FLAG
// Set to `true`  → onboarding runs every launch (for UI testing)
// Set to `false` → normal behaviour (onboarding runs only once)
// ─────────────────────────────────────────────────────────────────────────────
#if DEBUG
private let RESET_ONBOARDING_EACH_LAUNCH = true

// ─────────────────────────────────────────────────────────────────────────────
// 🧪 SCAN GATE FLAG
// Set to `true`  → share gate disabled, unlimited scans (for LLM testing)
// Set to `false` → share gate active after 2 free scans
// ─────────────────────────────────────────────────────────────────────────────
private let DISABLE_SCAN_GATE = true
#endif

@MainActor
public class AppState: ObservableObject {
    private static let analysisCacheVersion = "2026-02-23-reference-v2"
    private let authService: AuthService
    private let onboardingRepository: OnboardingRepository
    private let analysisRepository: AnalysisRepository
    private let skinAnalysisService: SkinAnalysisService
    private let faceDetectionService: FaceDetectionService
    private var pendingScanImageData: Data?

    @Published public var currentRoute: [AppRoute] = []
    @Published public var isAuthenticated: Bool = false
    @Published public var hasCompletedOnboarding: Bool = false
    @AppStorage("appTheme") public var appTheme: String = "pastel"
    @AppStorage("scanShareCount") public var scanShareCount: Int = 0   // times shared to unlock scans
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

    /// True when the user has unlocked unlimited scans via sharing (shared 3 times)
    public var scansUnlocked: Bool {
#if DEBUG
        if DISABLE_SCAN_GATE { return true }
#endif
        return scanShareCount >= 3
    }
    /// Free scan quota — first 2 are always free
    public static let freeScanQuota = 2


    public init(
        authService: AuthService,
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        skinAnalysisService: SkinAnalysisService,
        faceDetectionService: FaceDetectionService
    ) {
        self.authService = authService
        self.onboardingRepository = onboardingRepository
        self.analysisRepository = analysisRepository
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

    public func bootstrap() async {
        isBootstrapping = true
        isGoogleConfigured = authService.isGoogleSignInAvailable
        defer { isBootstrapping = false }

        let restoredSession = await authService.restoreSession()
        guard let restoredSession else {
            currentSession = nil
            isAuthenticated = false
            hasCompletedOnboarding = false
            shouldOpenHomeDeepDive = false
            homeDeepDiveAnalysisId = nil
            pendingScanImageData = nil
            scanErrorMessage = nil
            clearOnboardingDraft()
            recentAnalyses = []
            presentAsRoot(.auth)
            return
        }

#if DEBUG
        if RESET_ONBOARDING_EACH_LAUNCH {
            try? onboardingRepository.resetOnboarding(userId: restoredSession.localUserId)
        }
#endif

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

        currentSession = nil
        isAuthenticated = false
        hasCompletedOnboarding = false
        shouldOpenHomeDeepDive = false
        homeDeepDiveAnalysisId = nil
        pendingScanImageData = nil
        scanErrorMessage = nil
        clearOnboardingDraft()
        recentAnalyses = []
        presentAsRoot(.auth)
    }

    public func setOnboardingGender(_ gender: String?) {
        onboardingDraftGender = gender
    }

    public func setOnboardingSkinTypes(_ skinTypes: Set<String>) {
        onboardingDraftSkinTypes = skinTypes
    }

    public func setOnboardingGoal(_ goal: String?) {
        onboardingDraftGoal = goal
    }

    public func setOnboardingRoutine(_ routine: String?) {
        onboardingDraftRoutine = routine
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
            hasCompletedOnboarding = true
            clearOnboardingDraft()
            try loadRecentAnalyses(for: session.localUserId)
            presentAsRoot(.home)
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
            try loadRecentAnalyses(for: userId)
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

    public func queueScanImageData(_ imageData: Data) {
        pendingScanImageData = imageData
        scanErrorMessage = nil
    }

    public func processPendingAnalysis() async -> String? {
        guard let userId = currentSession?.localUserId else {
            scanErrorMessage = "Please sign in before running a scan."
            return nil
        }

        guard let imageData = pendingScanImageData else {
            scanErrorMessage = "Select a selfie before starting analysis."
            return nil
        }

        pendingScanImageData = nil
        let rawImageHash = ImageFingerprint.stableHash(for: imageData)
        let imageHash = rawImageHash.map { "\(Self.analysisCacheVersion):\($0)" }

        if let imageHash {
            do {
                if let existing = try analysisRepository.analysis(byImageHash: imageHash, userId: userId) {
                    try analysisRepository.touchAnalysis(id: existing.id)
                    try loadRecentAnalyses(for: userId)
                    scanErrorMessage = nil
                    return existing.id
                }
            } catch {
                // If cache lookup fails, continue with a fresh analysis.
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

    public func openAnalysisInHomeDeepDive(_ analysisId: String? = nil) {
        homeDeepDiveAnalysisId = analysisId
        shouldOpenHomeDeepDive = true
        presentAsRoot(.home)
    }

    private func setAuthenticatedState(with session: AuthSession) async {
        currentSession = session
        isAuthenticated = true
        scanErrorMessage = nil

        do {
            hasCompletedOnboarding = try onboardingRepository.hasCompletedOnboarding(userId: session.localUserId)
            if hasCompletedOnboarding {
                try loadRecentAnalyses(for: session.localUserId)
                presentAsRoot(.home)
            } else {
                presentAsRoot(.onboardingGender)
            }
        } catch {
            hasCompletedOnboarding = false
            presentAsRoot(.onboardingGender)
        }
    }

    private func loadRecentAnalyses(for userId: String) throws {
        recentAnalyses = try analysisRepository.fetchRecentAnalyses(userId: userId, limit: 20)
    }

    private func clearOnboardingDraft() {
        onboardingDraftGender = nil
        onboardingDraftSkinTypes = []
        onboardingDraftGoal = nil
        onboardingDraftRoutine = nil
    }

    private func userFacingError(from error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        return error.localizedDescription
    }
}
