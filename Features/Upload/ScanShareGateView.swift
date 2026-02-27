import SwiftUI
import UIKit

struct ScanShareGateView: View {
    @EnvironmentObject var appState: AppState
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -160, y: -200)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { appState.goBack() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .padding(12)
                            .background(AppTheme.shared.current.colors.surface)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.shared.current.colors.accent.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    }
                    .opacity(contentOpacity)
                    .scaleEffect(contentOpacity)

                    VStack(spacing: 10) {
                        Text("Invite Friends")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("You get 2 free scans after install.\nAfter that, each extra free scan unlocks after 2 validated referrals.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }
                    .opacity(contentOpacity)
                    .offset(y: slideOffset)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            statPill(title: "Invites sent", value: "\(appState.referralShareCount)")
                            statPill(title: "Validated", value: "\(appState.validatedReferralCount)")
                        }

                        Text(validationProgressCopy)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)

                        Text("Opening the share sheet does not unlock scans by itself. Rewards should only be granted after a friend signs up from your invite.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(contentOpacity)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [
                "I’m using Skin Score to track my cosmetic skin progress with AI. Check it out 👇 https://github.com/Henglerr/SkinappIOSready"
            ]) { activityType in
                appState.recordReferralShareAttempt(activityType: activityType)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { contentOpacity = 1 }
            withAnimation(.easeOut(duration: 0.6)) { slideOffset = 0 }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showShareSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Send Invite")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppTheme.shared.current.colors.primaryGradient)
                    .cornerRadius(20)
                    .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 12, x: 0, y: 4)
                }

                Button { appState.goBack() } label: {
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .underline()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 8)
            .background(AppTheme.shared.current.colors.bgPrimary)
        }
    }

    private var validationProgressCopy: String {
        if !appState.canEarnReferralRewards {
            return "Referral rewards require an Apple or Google account so invites can be tied to a real user."
        }

        if appState.validatedReferralCount > 0 {
            return "\(appState.validatedReferralsUntilNextFreeScan) more validated referral\(appState.validatedReferralsUntilNextFreeScan == 1 ? "" : "s") until your next free scan"
        }

        return "Extra scans unlock after 2 new users actually sign up from your invite."
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.shared.current.colors.accent.opacity(0.10))
        .cornerRadius(16)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: ((UIActivity.ActivityType?) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            if completed { onCompletion?(activityType) }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
