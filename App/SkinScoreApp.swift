import SwiftUI
import SwiftData
import GoogleSignIn
import UserNotifications

@main
struct SkinLitApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer?
    private let appState: AppState?
    private let launchFailureMessage: String?

    init() {
        switch Self.bootstrapLocalStorage() {
        case let .success(container, launchWarningMessage):
            self.modelContainer = container
            self.launchFailureMessage = nil

            let context = ModelContext(container)
            let userRepository = UserRepository(context: context)
            let onboardingDraftRepository = OnboardingDraftRepository(context: context)
            let onboardingRepository = OnboardingRepository(context: context)
            let analysisRepository = AnalysisRepository(context: context)
            let skinJourneyRepository = SkinJourneyRepository(context: context)
            let analysisPhotoStore = FileSystemAnalysisPhotoStore()
            let settingsRepository = SettingsRepository(context: context)
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationService = LocalNotificationService(center: notificationCenter)
            let liveBillingService = StoreKitBillingService(productIDs: AppConfig.subscriptionProductIds)
#if DEBUG
            let billingService: any BillingService = DeveloperFallbackBillingService(
                primary: liveBillingService,
                fallback: MockBillingService(productIDs: AppConfig.subscriptionProductIds)
            )
#else
            let billingService: any BillingService = liveBillingService
#endif
            let faceDetectionService = VisionFaceDetectionService()
            let backendClient = ConvexBackendClient()
            let backendSessionStore: any BackendSessionStoring = AppConfig.isDeveloperModeEnabled()
                ? InMemoryBackendSessionStore()
                : BackendSessionStore()
            let backendSessionService = BackendSessionService(
                client: backendClient,
                store: backendSessionStore
            )
            let remoteOnboardingRepository = RemoteOnboardingRepository(
                client: backendClient,
                sessionService: backendSessionService
            )
            let remoteScanRepository = RemoteScanRepository(
                client: backendClient,
                sessionService: backendSessionService
            )
            let remoteJourneyRepository = RemoteJourneyRepository(
                client: backendClient,
                sessionService: backendSessionService
            )
            let remoteReferralRepository = RemoteReferralRepository(
                client: backendClient,
                sessionService: backendSessionService
            )
            let skinAnalysisService = CompositeSkinAnalysisService(
                remoteRepository: remoteScanRepository
            )

            notificationCenter.delegate = notificationService

            let authService = LocalAuthService(
                userRepository: userRepository,
                onboardingDraftRepository: onboardingDraftRepository,
                onboardingRepository: onboardingRepository,
                analysisRepository: analysisRepository,
                skinJourneyRepository: skinJourneyRepository,
                analysisPhotoStore: analysisPhotoStore,
                settingsRepository: settingsRepository,
                backendSessionService: backendSessionService
            )

            self.appState = AppState(
                authService: authService,
                onboardingDraftRepository: onboardingDraftRepository,
                onboardingRepository: onboardingRepository,
                analysisRepository: analysisRepository,
                skinJourneyRepository: skinJourneyRepository,
                analysisPhotoStore: analysisPhotoStore,
                settingsRepository: settingsRepository,
                notificationService: notificationService,
                billingService: billingService,
                skinAnalysisService: skinAnalysisService,
                qualityOverrideAnalysisService: remoteScanRepository,
                faceDetectionService: faceDetectionService,
                remoteOnboardingRepository: remoteOnboardingRepository,
                remoteScanRepository: remoteScanRepository,
                remoteJourneyRepository: remoteJourneyRepository,
                remoteReferralRepository: remoteReferralRepository,
                launchWarningMessage: launchWarningMessage
            )
        case let .failure(message):
            self.modelContainer = nil
            self.appState = nil
            self.launchFailureMessage = message
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let appState, let modelContainer {
                RootView()
                    .environmentObject(appState)
                    .modelContainer(modelContainer)
                    .task {
                        await appState.handleScenePhase(scenePhase)
                    }
                    .onChange(of: scenePhase) { _, newValue in
                        Task {
                            await appState.handleScenePhase(newValue)
                        }
                    }
                    .onOpenURL { url in
                        let handledByGoogle = GIDSignIn.sharedInstance.handle(url)
                        if !handledByGoogle {
                            appState.handleIncomingURL(url)
                        }
                    }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        if let url = activity.webpageURL {
                            appState.handleIncomingURL(url)
                        }
                    }
            } else {
                LaunchFailureView(message: launchFailureMessage ?? "SkinLit could not start because local storage could not be initialized.")
            }
        }
    }

    private enum StorageBootstrapResult {
        case success(container: ModelContainer, launchWarningMessage: String?)
        case failure(message: String)
    }

    private static func bootstrapLocalStorage() -> StorageBootstrapResult {
        do {
            let container = try LocalStore.makeContainer()
            return .success(container: container, launchWarningMessage: nil)
        } catch {
            do {
                let container = try LocalStore.makeContainer(storageMode: .inMemory)
                return .success(
                    container: container,
                    launchWarningMessage: "SkinLit could not restore your saved local data for this launch. You can keep using the app, but recent history and settings may be temporarily unavailable."
                )
            } catch {
                return .failure(
                    message: "SkinLit could not initialize local storage for this launch. Please restart the app or reinstall it if the problem persists."
                )
            }
        }
    }
}

private struct LaunchFailureView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("SkinLit could not start")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Link("Contact Support", destination: AppConfig.supportURL)
                    .font(.headline)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 420)
        }
        .background(Color(.systemGroupedBackground))
    }
}
