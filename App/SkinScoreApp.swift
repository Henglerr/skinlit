import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct SkinScoreApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var appState: AppState

    init() {
        do {
            let container = try LocalStore.makeContainer()
            self.modelContainer = container

            let context = ModelContext(container)
            let userRepository = UserRepository(context: context)
            let onboardingRepository = OnboardingRepository(context: context)
            let analysisRepository = AnalysisRepository(context: context)
            let settingsRepository = SettingsRepository(context: context)
            let billingService = StoreKitBillingService(productIDs: AppConfig.subscriptionProductIds)
            let skinAnalysisService = CompositeSkinAnalysisService()
            let faceDetectionService = VisionFaceDetectionService()

            let authService = LocalAuthService(
                userRepository: userRepository,
                onboardingRepository: onboardingRepository,
                analysisRepository: analysisRepository,
                settingsRepository: settingsRepository
            )

            _appState = StateObject(
                wrappedValue: AppState(
                    authService: authService,
                    onboardingRepository: onboardingRepository,
                    analysisRepository: analysisRepository,
                    billingService: billingService,
                    skinAnalysisService: skinAnalysisService,
                    faceDetectionService: faceDetectionService
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
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
