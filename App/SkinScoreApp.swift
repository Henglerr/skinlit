import SwiftUI
import SwiftData
import GoogleSignIn
import UserNotifications

@main
struct SkinScoreApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer
    @StateObject private var appState: AppState

    init() {
        do {
            let container = try LocalStore.makeContainer()
            self.modelContainer = container

            let context = ModelContext(container)
            let userRepository = UserRepository(context: context)
            let onboardingDraftRepository = OnboardingDraftRepository(context: context)
            let onboardingRepository = OnboardingRepository(context: context)
            let analysisRepository = AnalysisRepository(context: context)
            let skinJourneyRepository = SkinJourneyRepository(context: context)
            let settingsRepository = SettingsRepository(context: context)
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationService = LocalNotificationService(center: notificationCenter)
            let billingService = StoreKitBillingService(productIDs: AppConfig.subscriptionProductIds)
            let faceDetectionService = VisionFaceDetectionService()
            let backendClient = ConvexBackendClient()
            let backendSessionService = BackendSessionService(client: backendClient)
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
                settingsRepository: settingsRepository,
                backendSessionService: backendSessionService
            )

            _appState = StateObject(
                wrappedValue: AppState(
                    authService: authService,
                    onboardingDraftRepository: onboardingDraftRepository,
                    onboardingRepository: onboardingRepository,
                    analysisRepository: analysisRepository,
                    skinJourneyRepository: skinJourneyRepository,
                    settingsRepository: settingsRepository,
                    notificationService: notificationService,
                    billingService: billingService,
                    skinAnalysisService: skinAnalysisService,
                    faceDetectionService: faceDetectionService,
                    remoteOnboardingRepository: remoteOnboardingRepository,
                    remoteScanRepository: remoteScanRepository,
                    remoteJourneyRepository: remoteJourneyRepository
                )
            )
        } catch {
            fatalError("Failed to initialize local storage: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
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
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
