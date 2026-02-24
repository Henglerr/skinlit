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
            
            // Pulsing glow behind the ring
            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .scaleEffect(ringScale)
            
            VStack(spacing: 48) {
                Spacer()
                
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 6)
                        .frame(width: 140, height: 140)
                    
                    // Spinning gradient arc
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
                    
                    // Center icon
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
    @State private var selectedPlan = "monthly"
    @State private var isLoading = false
    
    let plans: [(id: String, title: String, price: String, period: String, trial: String?, badge: String?)] = [
        ("weekly",  "Weekly",  "$2.99",  "/ week",  nil,        nil),
        ("monthly", "Monthly", "$6.99",  "/ month", "3-day free trial", "MOST POPULAR"),
        ("yearly",  "Yearly",  "$29.99", "/ year",  "3-day free trial", "BEST VALUE"),
    ]
    
    let features = [
        "Detailed score per criterion",
        "Full AI skin analysis",
        "Weekly progress history",
        "Community feed unlimited",
        "Notifications when rated",
        "Complete Skin Profile",
        "Unlimited analyses"
    ]
    
    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            
            // Ambient
            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 350)
                .blur(radius: 80)
                .offset(y: -300)
            
            VStack(spacing: 0) {
                // Close
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
                    VStack(spacing: 28) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "faceid")
                                .font(.system(size: 44, weight: .thin))
                                .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                            
                            Text("Unlock Skin Score")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            
                            Text("Get the full analysis, tips, and track your glow-up over time.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Features list
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
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1))
                        
                        // Plan selector
                        VStack(spacing: 12) {
                            ForEach(plans, id: \.id) { plan in
                                PaywallPlanRow(
                                    plan: plan,
                                    isSelected: selectedPlan == plan.id,
                                    onTap: { selectedPlan = plan.id }
                                )
                            }
                        }
                        
                        // CTA
                        PrimaryButton(
                            selectedPlan == "weekly" ? "Start Now" : "Start Free Trial",
                            icon: "lock.open.fill",
                            isEnabled: !isLoading
                        ) {
                            isLoading = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isLoading = false
                                appState.goBack()
                            }
                        }
                        
                        Button(action: {}) {
                            Text("Restore Purchase")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct PaywallPlanRow: View {
    let plan: (id: String, title: String, price: String, period: String, trial: String?, badge: String?)
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
                    if let trial = plan.trial {
                        Text(trial)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.price)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.textPrimary)
                    Text(plan.period)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }
            }
            .padding(20)
            .background(isSelected ? AppTheme.shared.current.colors.accentSoft : AppTheme.shared.current.colors.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
