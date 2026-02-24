import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSplash = true
    @State private var didBootstrap = false
    
    var body: some View {
        Group {
            if showSplash {
                SplashView()
                    .onAppear {
                        guard !didBootstrap else { return }
                        didBootstrap = true

                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await appState.bootstrap()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSplash = false
                            }
                        }
                    }
            } else {
                NavigationStack(path: $appState.currentRoute) {
                    Group {
                        if let root = appState.currentRoute.first {
                            viewForRoute(root)
                        } else {
                            AuthView() // Fallback
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        viewForRoute(route)
                    }
                }
                // Rebuild all views when the theme changes so AppTheme.shared.current re-evaluates
                .id(appState.appTheme)
                .preferredColorScheme(appState.appTheme == "purple" ? .dark : nil)
            }
        }
    }
    
    @ViewBuilder
    private func viewForRoute(_ route: AppRoute) -> some View {
        switch route {
        case .auth:
            AuthView()
        case .onboardingGender:
            OnboardingGenderView()
        case .onboardingTheme:
            OnboardingThemeView()
        case .onboardingSkintype:
            OnboardingSkintypeView()
        case .onboardingGoal:
            OnboardingGoalView()
        case .onboardingRoutine:
            OnboardingRoutineView()
        case .onboardingRating:
            OnboardingRatingView()
        case .onboardingTransition:
            OnboardingTransitionView()
        case .home:
            HomeView()
        case .upload:
            UploadView()
        case .scanPrep(let useCamera):
            ScanPrepView(sourceType: useCamera ? .camera : .photoLibrary)
        case .shareGate:
            ScanShareGateView()
        case .loadingAnalysis:
            LoadingView()
        case .paywall:
            PaywallView()
        }
    }
}
