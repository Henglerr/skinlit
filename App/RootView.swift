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
                .overlay(alignment: .top) {
                    if let warningMessage = appState.launchWarningMessage {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.warning)

                            Text(warningMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button {
                                appState.dismissLaunchWarning()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.shared.current.colors.surface)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
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
