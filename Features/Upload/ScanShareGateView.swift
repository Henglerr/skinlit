import SwiftUI

struct ScanShareGateView: View {
    @EnvironmentObject var appState: AppState
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30
    @State private var friendScales: [CGFloat] = [1, 1, 1]
    @State private var shareCount: Int = 0   // local mirror, counts within this session
    @State private var showShareSheet = false

    private let sharesNeeded = 3

    // How many shares still needed
    private var sharesLeft: Int { max(0, sharesNeeded - appState.scanShareCount) }
    private var isUnlocked: Bool { appState.scansUnlocked }

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
                // ── Top bar ─────────────────────────────────────────────────
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

                // ── Main content ─────────────────────────────────────────────
                VStack(spacing: 28) {

                    // Icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.shared.current.colors.accent.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: isUnlocked ? "checkmark.seal.fill" : "person.badge.plus.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    }
                    .opacity(contentOpacity)
                    .scaleEffect(contentOpacity)
                    .animation(.spring(response: 0.7, dampingFraction: 0.7), value: isUnlocked)

                    // Headline
                    VStack(spacing: 10) {
                        Text(isUnlocked ? "Scans Unlocked! 🎉" : "You've used your\n2 free scans")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(isUnlocked
                             ? "Enjoy unlimited scans. Keep tracking\nyour skin's progress, it's on us! ✨"
                             : "Share Skin Score with \(sharesLeft) friend\(sharesLeft == 1 ? "" : "s") to unlock\nyour next scan — totally free, forever.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }
                    .opacity(contentOpacity)
                    .offset(y: slideOffset)

                    // Friend tracker — 3 circles
                    if !isUnlocked {
                        HStack(spacing: 20) {
                            ForEach(0..<sharesNeeded, id: \.self) { i in
                                let filled = appState.scanShareCount > i
                                ZStack {
                                    Circle()
                                        .fill(filled
                                              ? AppTheme.shared.current.colors.success.opacity(0.15)
                                              : AppTheme.shared.current.colors.surfaceHigh)
                                        .frame(width: 62, height: 62)
                                        .overlay(
                                            Circle().stroke(filled
                                                ? AppTheme.shared.current.colors.success
                                                : AppTheme.shared.current.colors.textTertiary.opacity(0.3),
                                                lineWidth: 2)
                                        )
                                    if filled {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(AppTheme.shared.current.colors.success)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        Image(systemName: "person.crop.circle")
                                            .font(.system(size: 26))
                                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                                    }
                                }
                                .scaleEffect(friendScales[i])
                            }
                        }
                        .opacity(contentOpacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [
                "I'm using Skin Score to track and improve my skin health with AI! 🧬✨ Try it free 👇 https://apps.apple.com/app/skin-score"
            ]) {
                // Called when share is completed
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                    let newCount = min(appState.scanShareCount + 1, sharesNeeded)
                    appState.scanShareCount = newCount

                    // Bounce the newly filled circle
                    let idx = newCount - 1
                    if idx < sharesNeeded {
                        friendScales[idx] = 1.4
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                friendScales[idx] = 1.0
                            }
                        }
                    }
                }

                // If all shares done, go straight to scan
                if appState.scansUnlocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        appState.navigate(to: .loadingAnalysis)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { contentOpacity = 1 }
            withAnimation(.easeOut(duration: 0.6)) { slideOffset = 0 }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if isUnlocked {
                    PrimaryButton("Scan My Skin Now 🚀") {
                        appState.navigate(to: .loadingAnalysis)
                    }
                } else {
                    // Share button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Share with a Friend")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppTheme.shared.current.colors.primaryGradient)
                        .cornerRadius(20)
                        .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 12, x: 0, y: 4)
                    }

                    // Or upgrade to PRO
                    Button { appState.navigate(to: .paywall) } label: {
                        Text("Or unlock PRO for unlimited scans")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .underline()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 8)
            .background(AppTheme.shared.current.colors.bgPrimary)
        }
    }
}

// MARK: - UIKit share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            if completed { onCompletion?() }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
