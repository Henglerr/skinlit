import SwiftUI

/// Shown before the camera/picker, educates the user on how to take
/// the best selfie for accurate AI skin analysis.
struct ScanPrepView: View {
    @EnvironmentObject var appState: AppState
    @State private var sourceType: UIImagePickerController.SourceType
    @State private var contentOpacity: Double = 0
    @State private var checkOpacity: [Double] = [0, 0, 0, 0, 0]
    @State private var showImagePicker = false
    @State private var pickerErrorMessage: String?
    @State private var isProcessing = false

    init(sourceType: UIImagePickerController.SourceType) {
        _sourceType = State(initialValue: sourceType)
    }

    private let tips: [(icon: String, text: String, detail: String)] = [
        ("sun.max.fill",
         "Natural light, facing you",
         "Sit in front of a window. Avoid side shadows or lamps behind you."),
        ("ruler.fill",
         "30–50 cm from the camera",
         "Arm's length away. Too close distorts; too far loses skin detail."),
        ("face.smiling",
         "Face centred, looking straight ahead",
         "Chin parallel to floor. Both cheeks should be equally visible."),
        ("wind",
         "Hair away from your face",
         "Pull hair back so forehead, temples, and jaw are fully exposed."),
        ("sparkles",
         "No filters, clean skin",
         "Wash your face first. No makeup or filters — the AI reads your real skin."),
    ]

    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: 160, y: -220)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Top bar ──────────────────────────────────────────────────
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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // ── Headline ─────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before we scan")
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            Text("Follow these steps so the AI can read your skin accurately — it makes a real difference.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .lineSpacing(4)
                        }
                        .opacity(contentOpacity)
                        .padding(.top, 8)

                        // ── Tip cards ────────────────────────────────────────
                        VStack(spacing: 12) {
                            ForEach(tips.indices, id: \.self) { i in
                                TipCard(
                                    step: i + 1,
                                    icon: tips[i].icon,
                                    text: tips[i].text,
                                    detail: tips[i].detail
                                )
                                .opacity(checkOpacity[i])
                                .offset(y: checkOpacity[i] == 0 ? 16 : 0)
                            }
                        }

                        Text("By continuing, your selfie is uploaded securely for cloud-based cosmetic AI analysis. This is not medical advice.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.shared.current.colors.surface)
                            .cornerRadius(12)

                        // ── Error message ────────────────────────────────────
                        if let msg = pickerErrorMessage ?? appState.scanErrorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppTheme.shared.current.colors.warning)
                                Text(msg)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.shared.current.colors.warning.opacity(0.08))
                            .cornerRadius(12)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: sourceType) { image in
                handlePickedImage(image)
            }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(AppTheme.shared.current.colors.accent)
                        Text("Preparing your scan…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .cornerRadius(22)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { contentOpacity = 1 }
            for i in 0..<tips.count {
                withAnimation(.easeOut(duration: 0.45).delay(0.15 + Double(i) * 0.10)) {
                    checkOpacity[i] = 1
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton(
                    sourceType == .camera ? "I'm Ready — Open Camera" : "I'm Ready — Choose Photo"
                ) {
                    openPicker()
                }

                Button { appState.goBack() } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 8)
            .background(AppTheme.shared.current.colors.bgPrimary)
        }
    }

    // MARK: - Actions

    private func openPicker() {
        pickerErrorMessage = nil
        appState.scanErrorMessage = nil
        guard appState.canRunScan else {
            appState.openPaywall()
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            pickerErrorMessage = sourceType == .camera
                ? "Camera unavailable on this device — choose from gallery instead."
                : "Photo library unavailable on this device."
            return
        }
        showImagePicker = true
    }

    private func handlePickedImage(_ image: UIImage?) {
        guard let image else { return }
        isProcessing = true
        Task {
            do {
                let data = try await FaceImageProcessor.process(image)
                await MainActor.run {
                    isProcessing = false
                    appState.queueScanImageData(data)
                    appState.navigate(to: .loadingAnalysis)
                }
            } catch let err as FaceImageProcessor.ProcessorError {
                await MainActor.run {
                    isProcessing = false
                    pickerErrorMessage = err.errorDescription
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    pickerErrorMessage = "Could not process this photo. Try another one."
                }
            }
        }
    }
}

// MARK: - Tip Card

private struct TipCard: View {
    let step: Int
    let icon: String
    let text: String
    let detail: String
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                expanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    // Step badge
                    ZStack {
                        Circle()
                            .fill(AppTheme.shared.current.colors.accent.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    }

                    Text(text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                }
                .padding(16)

                if expanded {
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(AppTheme.shared.current.colors.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
