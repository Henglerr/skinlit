import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct AuthView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppState
    @State private var orbRotation: Double = 0
    @State private var orbScale: CGFloat = 1.0
    @State private var contentOpacity: Double = 0

    private var pendingReferralCode: String? {
        AppConfig.normalizedReferralCode(appState.pendingReferralCode)
    }

    private var authEyebrow: String {
        pendingReferralCode == nil ? "Cloud Save Beta" : "Invite Saved"
    }

    private var authHelperCopy: String {
        if let pendingReferralCode {
            return "Your invite code \(pendingReferralCode) is saved on this device. Keep using SkinLit without an account, or sign in with Apple or Google when you are ready to claim it after onboarding."
        }
        return "Use SkinLit without an account. Sign in only if you want to save your progress to cloud beta later."
    }

    private var pendingReferralCopy: String? {
        guard let pendingReferralCode else { return nil }
        return "Code \(pendingReferralCode) is ready on this device. Keep exploring SkinLit locally, then sign in to claim it after onboarding."
    }
    
    var body: some View {
        ZStack {
            // Background
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            
            // Dynamic Ambient Orbs
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(AppTheme.shared.current.colors.accentGlow)
                        .frame(width: proxy.size.width * 1.5, height: proxy.size.width * 1.5)
                        .blur(radius: 80)
                        .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.3)
                        .rotationEffect(.degrees(orbRotation))
                        .scaleEffect(orbScale)
                    
                    Circle()
                        .fill(AppTheme.shared.current.colors.accentSoft)
                        .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                        .blur(radius: 60)
                        .offset(x: proxy.size.width * 0.4, y: proxy.size.height * 0.5)
                        .rotationEffect(.degrees(-orbRotation * 0.8))
                        .scaleEffect(1.5 - orbScale * 0.5)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    orbRotation = 360
                }
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    orbScale = 1.2
                }
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo & Typography
                VStack(spacing: 24) {
                    Image(systemName: "faceid")
                        .font(.system(size: 72, weight: .thin))
                        .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                        .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 30, x: 0, y: 0)
                    
                    Text("Discover your\nskin score")
                        .font(.system(size: 36, weight: .heavy, design: .default))
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Text(AppConfig.tagline)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }
                
                Spacer()
                
                // Auth Buttons Area
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text(authEyebrow)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                            .tracking(1.2)

                        Text(authHelperCopy)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    if let pendingReferralCopy {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.accent)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invite code saved")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                Text(pendingReferralCopy)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                    .lineSpacing(3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(AppTheme.shared.current.colors.surface.opacity(0.8))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(AppTheme.shared.current.colors.accent.opacity(0.14), lineWidth: 1)
                        )
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await appState.signInWithApple(result: result)
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 56)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .disabled(appState.isAuthLoading)
                    
                    GoogleSignInButton(
                        scheme: colorScheme == .dark ? .dark : .light,
                        style: .wide,
                        state: appState.isGoogleConfigured && !appState.isAuthLoading ? .normal : .disabled
                    ) {
                        guard appState.isGoogleConfigured else { return }
                        Task {
                            await appState.signInWithGoogle()
                        }
                    }
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .disabled(!appState.isGoogleConfigured || appState.isAuthLoading)

                    if appState.allowsGuestAccess {
                        Button(action: {
                            Task {
                                await appState.continueAsGuest()
                            }
                        }) {
                            Text(appState.isGuestSession ? "Keep using locally →" : "Use without account →")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                        .disabled(appState.isAuthLoading)
                    }

                    if appState.isAuthLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppTheme.shared.current.colors.accent)
                            .padding(.top, 4)
                    }

                    if !appState.isGoogleConfigured {
                        Text("Google sign-in is not configured in this build yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }

                    Text("Apple or Google sign-in is optional. Use it only to activate cloud save beta and sync your scans online.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    if let errorMessage = appState.authErrorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.error)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .background(
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary.opacity(0.8), AppTheme.shared.current.colors.bgPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 300)
                    }
                    .ignoresSafeArea()
                )
            }
            .opacity(contentOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                    contentOpacity = 1.0
                }
            }
        }
    }
}
