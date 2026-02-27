import SwiftUI

// MARK: - Loading View

struct LoadingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPhraseIndex = 0
    @State private var phraseOpacity: Double = 1
    @State private var ringRotation: Double = 0
    @State private var ringScale: CGFloat = 1.0
    @State private var hasStartedAnalysis = false

    let phrases = [
        "Analyzing hydration levels...",
        "Checking pores and texture...",
        "Measuring luminosity...",
        "Evaluating uniformity...",
        "Calculating your Skin Score..."
    ]

    let timer = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    private func popToLatestScanPrep() {
        if let index = appState.currentRoute.lastIndex(where: {
            if case .scanPrep = $0 { return true }
            return false
        }) {
            appState.currentRoute = Array(appState.currentRoute.prefix(index + 1))
            return
        }
        appState.presentAsRoot(.upload)
    }

    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()

            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .scaleEffect(ringScale)

            VStack(spacing: 48) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 6)
                        .frame(width: 140, height: 140)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    AppTheme.shared.current.colors.accentGradientStart,
                                    AppTheme.shared.current.colors.accentGradientEnd.opacity(0)
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(ringRotation))

                    Image(systemName: "faceid")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        ringRotation = 360
                    }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        ringScale = 1.2
                    }
                }

                Text(phrases[currentPhraseIndex])
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(phraseOpacity)
                    .onReceive(timer) { _ in
                        withAnimation(.easeOut(duration: 0.3)) { phraseOpacity = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
                            withAnimation(.easeIn(duration: 0.3)) { phraseOpacity = 1 }
                        }
                    }

                Spacer()
            }
            .padding(.horizontal, 40)
            .onAppear {
                guard !hasStartedAnalysis else { return }
                hasStartedAnalysis = true

                Task {
                    let startedAt = Date()
                    let analysisId = await appState.processPendingAnalysis()
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let minimumLoadingTime = 2.2

                    if elapsed < minimumLoadingTime {
                        let remaining = minimumLoadingTime - elapsed
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    }

                    if let analysisId {
                        appState.openAnalysisInHomeDeepDive(analysisId)
                    } else {
                        popToLatestScanPrep()
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var selectedPlanId: String? = nil
    @State private var showShareSheet = false

    private let features = [
        "Detailed score per criterion",
        "Full cosmetic AI skin analysis",
        "Weekly progress history",
        "Personalized routine suggestions",
        "Unlimited analyses"
    ]

    private var selectedPlan: PaywallPackage? {
        guard let selectedPlanId else { return appState.paywallPackages.first }
        return appState.paywallPackages.first(where: { $0.id == selectedPlanId }) ?? appState.paywallPackages.first
    }

    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()

            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 350)
                .blur(radius: 80)
                .offset(y: -300)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { appState.goBack() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .padding(10)
                            .background(AppTheme.shared.current.colors.surface)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        VStack(spacing: 12) {
                            Image(systemName: "faceid")
                                .font(.system(size: 44, weight: .thin))
                                .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)

                            Text("Unlock Skin Score PRO")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                            Text("Cosmetic wellness insights, progress tracking, and unlimited scans.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 12) {
                            ForEach(features, id: \.self) { feature in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.shared.current.colors.accent)
                                        .font(.system(size: 18))
                                    Text(feature)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(24)
                        .background(AppTheme.shared.current.colors.surface)
                        .cornerRadius(24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
                        )

                        if appState.paywallPackages.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Loading subscription options...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            }
                            .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(appState.paywallPackages) { plan in
                                    PaywallPlanRow(
                                        plan: plan,
                                        isSelected: resolvedSelectedPlanId == plan.id,
                                        onTap: { selectedPlanId = plan.id }
                                    )
                                }
                            }
                        }

                        if let error = appState.billingErrorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.error)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        PrimaryButton(
                            callToActionTitle,
                            icon: "lock.open.fill",
                            isEnabled: !appState.isPaywallLoading && selectedPlan != nil
                        ) {
                            guard let selectedPlan else { return }
                            Task {
                                let didActivate = await appState.purchaseSubscription(selectedPlan.id)
                                if didActivate {
                                    appState.goBack()
                                }
                            }
                        }

                        if appState.isPaywallLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(AppTheme.shared.current.colors.accent)
                        }

                        Button {
                            Task {
                                let didRestore = await appState.restoreSubscriptions()
                                if didRestore {
                                    appState.goBack()
                                }
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        }

                        Button {
                            showShareSheet = true
                        } label: {
                            Text("Unlock 1 extra scan after 2 friend sign-ups")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .underline()
                        }

                        VStack(spacing: 8) {
                            Text(autoRenewCopy)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 14) {
                                Button("Privacy") { openURL(AppConfig.privacyPolicyURL) }
                                Button("Terms") { openURL(AppConfig.termsURL) }
                                Button("Support") { openURL(AppConfig.supportURL) }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                        }

                        Text("SkinScore provides cosmetic wellness insights and is not a medical diagnosis.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                }
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
            if selectedPlanId == nil {
                selectedPlanId = appState.paywallPackages.first?.id
            }
            Task {
                await appState.refreshPaywallData()
                if selectedPlanId == nil {
                    selectedPlanId = appState.paywallPackages.first?.id
                }
            }
        }
    }

    private var resolvedSelectedPlanId: String {
        selectedPlanId ?? appState.paywallPackages.first?.id ?? ""
    }

    private var callToActionTitle: String {
        if let trial = selectedPlan?.trialDescription, !trial.isEmpty {
            return "Start \(trial)"
        }
        return "Subscribe Now"
    }

    private var autoRenewCopy: String {
        if let trial = selectedPlan?.trialDescription, !trial.isEmpty {
            return "\(trial), then \(selectedPlan?.priceText ?? "") per \(billingPeriodLabel). Auto-renews unless cancelled at least 24 hours before period end. Manage anytime in App Store account settings."
        }

        return "Subscription renews automatically unless cancelled at least 24 hours before period end. Manage anytime in App Store account settings."
    }

    private var billingPeriodLabel: String {
        let planId = resolvedSelectedPlanId.lowercased()
        if planId.contains("week") { return "week" }
        if planId.contains("year") || planId.contains("annual") { return "year" }
        if planId.contains("month") { return "month" }
        return "period"
    }
}

struct PaywallPlanRow: View {
    let plan: PaywallPackage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.surfaceHigh)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.shared.current.colors.accent)
                                .cornerRadius(100)
                        }
                    }
                    if let trial = plan.trialDescription {
                        Text(trial)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                    }
                }

                Spacer()

                Text(plan.priceText)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.textPrimary)
            }
            .padding(20)
            .background(isSelected ? AppTheme.shared.current.colors.accentSoft : AppTheme.shared.current.colors.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.textPrimary.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
