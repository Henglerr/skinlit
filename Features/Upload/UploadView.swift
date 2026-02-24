import SwiftUI
import UIKit

struct UploadView: View {
    @EnvironmentObject var appState: AppState
    @State private var showTip = true

    /// How many real scans have been done
    private var scanCount: Int { appState.recentAnalyses.count }

    /// Should we gate this scan behind sharing?
    private var needsShareUnlock: Bool {
        scanCount >= AppState.freeScanQuota && !appState.scansUnlocked
    }

    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { appState.goBack() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .padding(12)
                            .background(AppTheme.shared.current.colors.surface)
                            .clipShape(Circle())
                    }
                    Spacer()

                    // Scan counter badge
                    if !appState.scansUnlocked {
                        HStack(spacing: 5) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                            let remaining = max(0, AppState.freeScanQuota - scanCount)
                            Text(remaining > 0
                                 ? "\(remaining) free scan\(remaining == 1 ? "" : "s") left"
                                 : "Share to unlock")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.1))
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Icon / Preview Placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(AppTheme.shared.current.colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(
                                    AppTheme.shared.current.colors.primaryGradient,
                                    lineWidth: 2
                                )
                        )
                        .frame(width: 260, height: 320)
                        .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 30, x: 0, y: 10)

                    VStack(spacing: 16) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)

                        Text("Your selfie\nwill appear here")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Tip
                if showTip {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(AppTheme.shared.current.colors.warning)
                            .font(.system(size: 14))
                        Text("Use natural light for the most accurate result")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AppTheme.shared.current.colors.surface)
                    .cornerRadius(16)
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                }

                if let error = appState.scanErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.shared.current.colors.warning)
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.shared.current.colors.warning.opacity(0.10))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }



                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    PrimaryButton("Take a Selfie", icon: "camera.fill") {
                        appState.navigate(to: .scanPrep(useCamera: true))
                    }

                    Button(action: { appState.navigate(to: .scanPrep(useCamera: false)) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 18))
                            Text("Choose from Gallery")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppTheme.shared.current.colors.surface)
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .navigationBarHidden(true)
    }
}
