import AVFoundation
import SwiftUI
import Charts

// MARK: - Models

struct SkinMetric: Identifiable {
    let id: String
    let symbolName: String
    let score: Double
    let insight: SkinCriterionInsight?
    let isPremium: Bool
}

struct ScorePoint: Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
}

// MARK: - HomeView

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: HomeTab = .home
    @State private var selectedAnalysisId: String? = nil
    @State private var isLatestSummaryExpanded = false
    @State private var showDeleteAccountAlert = false
    @State private var referralCodeDraft = ""
    @State private var selectedJourneyDate = SkinJourneyRepository.startOfDay(for: Date())
    @State private var displayedJourneyMonth = Calendar.autoupdatingCurrent.date(
        from: Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: Date())
    ) ?? SkinJourneyRepository.startOfDay(for: Date())
    @State private var isJourneySheetPresented = false
    @State private var isGenericShareSheetPresented = false
    @State private var selectedRoutineMoment: RoutineMoment = RoutineMoment.current(for: Date())

    // ── Derived from real analysis data ──────────────────────────────────────
    private var mostRecentAnalysis: LocalAnalysis? { appState.recentAnalyses.first }
    private var activeAnalysis: LocalAnalysis? {
        guard let selectedAnalysisId else { return mostRecentAnalysis }
        return appState.recentAnalyses.first(where: { $0.id == selectedAnalysisId }) ?? mostRecentAnalysis
    }
    private var latestScore: Double { mostRecentAnalysis?.score ?? 0 }

    // Parse criteria JSON from currently active deep-dive analysis.
    private var latestCriteria: [String: Double] {
        guard let activeAnalysis else { return [:] }
        return criteria(from: activeAnalysis)
    }

    private var latestJourneyCriteria: [String: Double] {
        guard let mostRecentAnalysis else { return [:] }
        return criteria(from: mostRecentAnalysis)
    }

    private var latestCriterionInsights: [String: SkinCriterionInsight] {
        activeAnalysis?.criterionInsights ?? [:]
    }

    private var latestRoutineCriterionInsights: [String: SkinCriterionInsight] {
        mostRecentAnalysis?.criterionInsights ?? [:]
    }

    private var todayRoutineLog: SkinJourneyLog? {
        appState.skinJourneyLog(on: Date())
    }

    private var routineCompletedStepIDs: Set<String> {
        Set(todayRoutineLog?.routineStepIDs ?? [])
    }

    private var routineStatusIDs: Set<String> {
        Set(todayRoutineLog?.skinStatusIDs ?? [])
    }

    private var routinePlan: RoutineExperiencePlan {
        RoutineExperiencePlanner.makePlan(
            latestAnalysis: mostRecentAnalysis,
            recentAnalyses: appState.recentAnalyses,
            latestCriteria: latestJourneyCriteria,
            criterionInsights: latestRoutineCriterionInsights,
            userContext: appState.currentSkinAnalysisContext,
            recentLogs: appState.skinJourneyLogs,
            todayLog: todayRoutineLog,
            now: Date()
        )
    }

    private var shouldShowDeveloperPanels: Bool {
        AppConfig.isDeveloperModeEnabled()
    }

    private var isGuestMode: Bool {
        appState.isGuestSession || appState.currentSession == nil
    }

    private var pendingReferralCode: String? {
        AppConfig.normalizedReferralCode(appState.pendingReferralCode)
    }

    private var shouldShowGuestReferralPrompt: Bool {
        AppConfig.isReferralsEnabled() && isGuestMode && pendingReferralCode != nil
    }

#if DEBUG
    private var activeDebugMetadata: LocalAnalysisDebugMetadata? {
        activeAnalysis?.debugMetadata
    }
#endif

    // Build score history from real analyses (chronological)
    private var scoreHistory: [ScorePoint] {
        let sorted = appState.recentAnalyses
            .sorted { $0.createdAt < $1.createdAt }
        return Array(sorted.suffix(8)).map { analysis in
            ScorePoint(id: analysis.id, timestamp: analysis.createdAt, value: analysis.score)
        }
    }

    private var streakFireCount: Int {
        min(appState.scanDayStreakCount, 7)
    }

    private var streakValueLabel: String {
        appState.scanDayStreakCount == 1 ? "1 day" : "\(appState.scanDayStreakCount) days"
    }

    private var scanStreakSubtitle: String {
        "current run"
    }

    private var streakCompletionLabel: String {
        streakFireCount >= 7 ? "7 of 7 complete" : "\(streakFireCount) of 7 days"
    }

    private var totalScanSubtitle: String {
        appState.totalScanCount == 1 ? "scan saved" : "scans saved"
    }

    private var shouldOfferLatestSummaryExpansion: Bool {
        guard let summary = mostRecentAnalysis?.summary else { return false }
        return summary.count > 88 || summary.contains("\n")
    }

    // ── Metric definitions (free vs premium, with AI text) ───────────────────
    private var metrics: [SkinMetric] {
        guard activeAnalysis != nil else { return [] }   // no data yet = no metrics
        let allDefs: [(id: String, symbolName: String, isPremium: Bool)] = [
            ("Hydration", "drop.fill", false),
            ("Luminosity", "sparkles", false),
            ("Texture", "square.grid.3x3.fill", true),
            ("Uniformity", "circle.lefthalf.filled", true),
        ]
        return allDefs.map { def in
            let score = latestCriteria[def.id] ?? 0.0   // 0 = truly no data
            let isLockedPremium = def.isPremium && !appState.isProActive
            return SkinMetric(id: def.id, symbolName: def.symbolName, score: score,
                              insight: latestCriterionInsights[def.id],
                              isPremium: isLockedPremium)
        }
    }

    private var freeMetrics: [SkinMetric] { metrics.filter { !$0.isPremium } }
    private var lockedPremiumMetrics: [SkinMetric] { metrics.filter { $0.isPremium } }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                headerView
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.05))

                Text("Cosmetic wellness insights only — not a medical diagnosis.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                if let errorMessage = appState.homeErrorMessage {
                    homeErrorBanner(errorMessage)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                switch selectedTab {
                case .home:
                    homeContent.transition(.opacity)
                case .deepDive:
                    deepDiveContent.transition(.opacity)
                case .routine:
                    routineContent.transition(.opacity)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.refreshRecentAnalyses()
            appState.refreshSkinJourneyLogs()
            consumeDeepDiveIntentIfNeeded()
            referralCodeDraft = appState.pendingReferralCode ?? ""
            selectedRoutineMoment = RoutineMoment.current(for: Date())
        }
        .onChange(of: appState.shouldOpenHomeDeepDive) { _, _ in
            consumeDeepDiveIntentIfNeeded()
        }
        .onChange(of: appState.recentAnalyses.map(\.id)) { _, ids in
            if let selectedAnalysisId, !ids.contains(selectedAnalysisId) {
                self.selectedAnalysisId = nil
            }
        }
        .onChange(of: appState.pendingReferralCode) { _, newValue in
            referralCodeDraft = newValue ?? ""
        }
        .onChange(of: mostRecentAnalysis?.id) { _, _ in
            isLatestSummaryExpanded = false
        }
        .onDisappear {
            appState.clearHomeErrorMessage()
        }
        .alert(deleteAlertTitle, isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            if appState.isProActive && !isGuestMode {
                Button("Manage Subscription") {
                    openURL(AppConfig.manageSubscriptionsURL)
                }
            }
            Button(deleteConfirmationTitle, role: .destructive) {
                Task { await appState.deleteAccount() }
            }
        } message: {
            Text(deleteAccountMessage)
        }
        .sheet(isPresented: $isGenericShareSheetPresented) {
            ShareSheet(items: appState.genericShareItems)
        }
        .sheet(isPresented: $isJourneySheetPresented) {
            SkinJourneyLogSheet(
                date: selectedJourneyDate,
                existingLog: appState.skinJourneyLog(on: selectedJourneyDate),
                onSave: { routineStepIDs, treatmentIDs, skinStatusIDs, note in
                    appState.saveSkinJourneyLog(
                        date: selectedJourneyDate,
                        routineStepIDs: routineStepIDs,
                        treatmentIDs: treatmentIDs,
                        skinStatusIDs: skinStatusIDs,
                        note: note
                    )
                },
                onDelete: appState.skinJourneyLog(on: selectedJourneyDate) == nil ? nil : {
                    appState.deleteSkinJourneyLog(date: selectedJourneyDate)
                }
            )
        }
    }

    // MARK: - Tab Pill

    private var headerView: some View {
        ViewThatFits(in: .horizontal) {
            headerInlineLayout
            headerStackedLayout
        }
    }

    private var headerInlineLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            headerTitle
            Spacer(minLength: 12)
            headerControls
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var headerStackedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                headerTitle
                Spacer(minLength: 12)
                accountMenuButton
            }

            HStack(spacing: 10) {
                homeTabPill(label: "Home", tab: .home)
                homeTabPill(label: "Deep Dive", tab: .deepDive)
                homeTabPill(label: "Routine", tab: .routine)
                Spacer(minLength: 0)
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppConfig.appName)
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text("Track your skin's progress")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            homeTabPill(label: "Home", tab: .home)
            homeTabPill(label: "Deep Dive", tab: .deepDive)
            homeTabPill(label: "Routine", tab: .routine)
            accountMenuButton
        }
    }

    private var accountMenuButton: some View {
        Menu {
            if isGuestMode {
                Button {
                    appState.navigate(to: .auth)
                } label: {
                    Label("Activate Cloud Beta", systemImage: "icloud")
                }
            }

            Button {
                Task { _ = await appState.restoreSubscriptions() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }

            if AppConfig.isShareConfigured() {
                if AppConfig.isReferralsEnabled() {
                    if appState.canEarnReferralRewards {
                        Button {
                            appState.navigate(to: .shareGate)
                        } label: {
                            Label("Share App", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Button {
                        isGenericShareSheetPresented = true
                    } label: {
                        Label("Share App", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if !isGuestMode {
                Button {
                    Task { await appState.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Button(role: .destructive) {
                showDeleteAccountAlert = true
            } label: {
                Label(isGuestMode ? "Delete Local Data" : "Delete Account", systemImage: "trash")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.shared.current.colors.surface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.07), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func homeTabPill(label: String, tab: HomeTab) -> some View {
        let sel = selectedTab == tab
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab = tab
                if tab == .routine {
                    selectedRoutineMoment = RoutineMoment.current(for: Date())
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(sel ? AppTheme.shared.current.colors.bgPrimary : AppTheme.shared.current.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(sel ? AppTheme.shared.current.colors.textPrimary : Color.clear)
                .clipShape(Capsule())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Home Tab

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Main scan CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    appState.openUploadFlow()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(AppTheme.shared.current.colors.primaryGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(
                                color: AppTheme.shared.current.colors.accentGlow.opacity(0.16),
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 44, weight: .thin))
                                .foregroundColor(.black.opacity(0.75))
                            VStack(spacing: 4) {
                                Text("Scan Your Skin")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundColor(.black)
                                Text("Start a new cosmetic skin scan")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.55))
                            }
                        }
                        .padding(.vertical, 32)
                    }
                }
                .buttonStyle(ScaleButtonStyle())

                if shouldShowGuestReferralPrompt {
                    guestReferralPromptCard
                }

                if appState.canEarnReferralRewards {
                    referralClaimCard
                }

                if !appState.recentAnalyses.isEmpty, let latest = mostRecentAnalysis {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            ZStack {
                                Circle()
                                    .stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 4)
                                    .frame(width: 56, height: 56)
                                Circle()
                                    .trim(from: 0, to: CGFloat(latest.score / 10.0))
                                    .stroke(AppTheme.shared.current.colors.primaryGradient,
                                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 56, height: 56)
                                    .rotationEffect(.degrees(-90))
                                Text(String(format: "%.1f", latest.score))
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundColor(AppTheme.shared.current.colors.scoreColor)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Latest Score")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                Text("\(String(format: "%.1f", latest.score))/10 overall")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            }

                            Spacer(minLength: 0)
                        }

                        Text(latest.summary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .lineSpacing(3)
                            .lineLimit(isLatestSummaryExpanded ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            if shouldOfferLatestSummaryExpansion {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isLatestSummaryExpanded.toggle()
                                    }
                                } label: {
                                    Text(isLatestSummaryExpanded ? "Show Less" : "Read Full Review")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(AppTheme.shared.current.colors.accent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.shared.current.colors.accent.opacity(0.10))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer(minLength: 0)

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = .deepDive }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Deep Dive")
                                    Image(systemName: "arrow.right")
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.shared.current.colors.accent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(AppTheme.shared.current.colors.surface)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1))

                    // ── Skin Evolution ────────────────────────────────────────
                    SkinEvolutionSection(
                        analyses: appState.recentAnalyses,
                        scoreHistory: scoreHistory,
                        isLocked: !appState.isProActive,
                        onUnlock: { appState.openPaywall() },
                        onScanTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                appState.openUploadFlow()
                            }
                        }
                    )

                    SkinJourneySection(
                        logs: appState.skinJourneyLogs,
                        analysisEntries: appState.analysisCalendarEntries,
                        latestAnalysis: mostRecentAnalysis,
                        latestCriteria: latestJourneyCriteria,
                        isLocked: !appState.isProActive,
                        selectedDate: $selectedJourneyDate,
                        displayedMonth: $displayedJourneyMonth,
                        onUnlock: { appState.openPaywall() },
                        onLogToday: {
                            openJourneyEditor(for: Date())
                        },
                        onEditSelectedDay: {
                            openJourneyEditor(for: selectedJourneyDate)
                        },
                        onLogSelectedDay: {
                            openJourneyEditor(for: selectedJourneyDate)
                        }
                    )

                    // Recent list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Analyses")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        ForEach(appState.recentAnalyses, id: \.id) { item in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedAnalysisId = item.id
                                    selectedTab = .deepDive
                                }
                            } label: {
                                RecentAnalysisRow(analysis: item)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                } else {
                    // ── Skin Evolution empty state ─────────────────────────────
                    SkinEvolutionSection(
                        analyses: [],
                        scoreHistory: [],
                        isLocked: !appState.isProActive,
                        onUnlock: { appState.openPaywall() },
                        onScanTap: { appState.openUploadFlow() }
                    )
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var scanMomentumSection: some View {
        HStack(spacing: 12) {
            ScanStatTile(
                eyebrow: "STREAK",
                icon: "flame.fill",
                value: streakValueLabel,
                subtitle: scanStreakSubtitle,
                footnote: streakCompletionLabel,
                accent: AppTheme.shared.current.colors.warning,
                accentSoft: AppTheme.shared.current.colors.warning.opacity(0.18),
                flameCount: streakFireCount
            )

            ScanStatTile(
                eyebrow: "SCANS MADE",
                icon: "camera.viewfinder",
                value: "\(appState.totalScanCount)",
                subtitle: totalScanSubtitle,
                footnote: "All-time skin scan history",
                accent: AppTheme.shared.current.colors.accent,
                accentSoft: AppTheme.shared.current.colors.accent.opacity(0.16),
                flameCount: nil
            )
        }
    }

    private var routineContent: some View {
        ScrollView(showsIndicators: false) {
            RoutineHubView(
                plan: routinePlan,
                selectedMoment: $selectedRoutineMoment,
                completedStepIDs: routineCompletedStepIDs,
                selectedSkinStatusIDs: routineStatusIDs,
                isProActive: appState.isProActive,
                onToggleStep: toggleRoutineStep,
                onToggleStatus: toggleRoutineStatus,
                onEditLog: { openJourneyEditor(for: Date()) },
                onUnlockPro: { appState.openPaywall() },
                onScanTap: { appState.openUploadFlow() }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var deleteAccountMessage: String {
        if isGuestMode {
            return "Deleting local data removes your local-only SkinLit profile, onboarding progress, scans, and skin journey history from this device. Cloud save beta stays off unless you choose to activate it later."
        }

        if appState.isProActive {
            return "Deleting your SkinLit account removes your app profile, scan history, and stored cloud data. Apple billing continues until you cancel it in App Store subscriptions."
        }

        return "Deleting your SkinLit account removes your app profile, scan history, and stored cloud data."
    }

    private var deleteAlertTitle: String {
        isGuestMode ? "Delete Local Data?" : "Delete Account?"
    }

    private var deleteConfirmationTitle: String {
        isGuestMode ? "Delete Data" : "Delete"
    }

    private var guestReferralPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite Saved")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                    Text(guestReferralPromptCopy)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .lineSpacing(4)
                }

                Spacer(minLength: 0)

                if let pendingReferralCode {
                    statBadge(title: "Saved code", value: pendingReferralCode)
                        .frame(maxWidth: 112)
                }
            }

            Button {
                appState.navigate(to: .auth)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "icloud")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Activate Cloud Beta to Claim")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.shared.current.colors.primaryGradient)
                .cornerRadius(18)
            }

            Text("You can keep using the app locally now. Claiming the invite needs Apple or Google sign-in after onboarding.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .lineSpacing(3)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var guestReferralPromptCopy: String {
        guard let pendingReferralCode else {
            return "A referral code is saved on this device. Sign in later to claim it."
        }
        return "Invite code \(pendingReferralCode) is saved on this device. Sign in with Apple or Google when you are ready to claim it."
    }

    private var referralClaimCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Referral Rewards")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text("Invite friends with your code, or claim one after onboarding.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(appState.referralBonusScansEarned)")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                    Text("rewards")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                statBadge(title: "Validated", value: "\(appState.validatedReferralCount)")
                statBadge(title: "Shares", value: "\(appState.referralShareCount)")
                if let inviteCode = appState.referralInviteCode {
                    statBadge(title: "Your code", value: inviteCode)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Have a referral code?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                HStack(spacing: 10) {
                    TextField("Enter code", text: $referralCodeDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.55))
                        .cornerRadius(16)
                        .onChange(of: referralCodeDraft) { _, newValue in
                            appState.updatePendingReferralCode(newValue)
                        }

                    Button {
                        Task {
                            await appState.claimPendingReferralCode()
                        }
                    } label: {
                        Group {
                            if appState.isReferralLoading {
                                ProgressView()
                                    .tint(AppTheme.shared.current.colors.bgPrimary)
                            } else {
                                Text("Claim")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .frame(width: 92, height: 50)
                        .background(AppTheme.shared.current.colors.accent)
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .cornerRadius(16)
                    }
                    .disabled(appState.isReferralLoading || referralCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(appState.isReferralLoading || referralCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                }
            }

            if let successMessage = appState.referralSuccessMessage {
                Text(successMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
            }

            if let errorMessage = appState.referralErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.error)
            }

            Text("Track validated referrals and keep your invite code handy for friends who join.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .lineSpacing(3)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private func statBadge(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.5))
        .cornerRadius(14)
    }

    // MARK: - Deep Dive Tab

    private var deepDiveContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Skin Report Card ─────────────────────────────────────────
                skinReportCard

                if appState.recentAnalyses.isEmpty {
                    // ── Empty state ───────────────────────────────────────────
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                        Text("Do your first scan")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        Text("Your scan summary, AI analysis,\nand routine ideas will appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                        PrimaryButton("Scan My Skin Now") {
                            appState.openUploadFlow()
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.shared.current.colors.surface)
                    .cornerRadius(24)

                } else {
                    scanMomentumSection

                    // ── Free Metrics ──────────────────────────────────────────
                    HStack {
                        Text("INCLUDED").font(.system(size: 10, weight: .heavy)).kerning(1.4)
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(freeMetrics) { metric in
                        MetricDetailCard(
                            metric: metric,
                            history: metricHistory(for: metric.id),
                            onUnlock: { appState.openPaywall() }
                        )
                    }

                    if !lockedPremiumMetrics.isEmpty {
                        // ── Premium Metrics ───────────────────────────────────────
                        HStack {
                            Text("PRO").font(.system(size: 10, weight: .heavy)).kerning(1.4)
                                .foregroundColor(AppTheme.shared.current.colors.accent)
                            Spacer()
                            Button { appState.openPaywall() } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.open.fill").font(.system(size: 10))
                                    Text("Unlock All").font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(AppTheme.shared.current.colors.accent)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 4)

                        ForEach(lockedPremiumMetrics) { metric in
                            MetricDetailCard(
                                metric: metric,
                                history: [],
                                onUnlock: { appState.openPaywall() }
                            )
                        }
                    }
                } // end else (has analyses)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Skin Report Card (consolidated view at top)

    private var skinReportCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top: score + new scan button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mostRecentAnalysis == nil ? "No scan yet" : "Skin Report")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .kerning(0.5)
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(mostRecentAnalysis == nil ? "—" : String(format: "%.1f", latestScore))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(AppTheme.shared.current.colors.scoreColor)
                        if mostRecentAnalysis != nil {
                            Text("/ 10")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .padding(.bottom, 7)
                        }
                    }
                    if let analysis = mostRecentAnalysis {
                        Text(analysis.skinTypeDetected)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                    }
                }

                Spacer()

                Button {
                    appState.openUploadFlow()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 22))
                        Text("New Scan")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                    .frame(width: 72, height: 72)
                    .background(AppTheme.shared.current.colors.primaryGradient)
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.shared.current.colors.accentGlow.opacity(0.18), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(AppTheme.shared.current.colors.textPrimary.opacity(0.06))
                .padding(.horizontal, 20)

            VStack(spacing: 11) {
                ForEach(metrics) { metric in
                    HStack(spacing: 10) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(
                                metric.isPremium
                                    ? AppTheme.shared.current.colors.textTertiary
                                    : AppTheme.shared.current.colors.accent
                            )
                            .frame(width: 20)

                        Text(metric.id)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(
                                metric.isPremium
                                    ? AppTheme.shared.current.colors.textTertiary
                                    : AppTheme.shared.current.colors.textPrimary
                            )
                            .frame(width: 84, alignment: .leading)

                        if metric.isPremium {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.shared.current.colors.surfaceHigh)
                                    .frame(height: 7)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.shared.current.colors.accent.opacity(0.18))
                                    .frame(width: 48, height: 7)
                            }
                            Text("PRO")
                                .font(.system(size: 8, weight: .heavy))
                                .kerning(0.5)
                                .foregroundColor(AppTheme.shared.current.colors.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                                .cornerRadius(4)
                                .frame(width: 32)
                        } else {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppTheme.shared.current.colors.surfaceHigh)
                                        .frame(height: 7)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(scoreGradient(for: metric.score))
                                        .frame(width: geo.size.width * CGFloat(metric.score / 10.0), height: 7)
                                }
                            }
                            .frame(height: 7)

                            Text(String(format: "%.1f", metric.score))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(scoreColor(for: metric.score))
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: AppTheme.shared.current.colors.textPrimary.opacity(0.04), radius: 16, x: 0, y: 6)
    }

    private func homeErrorBanner(_ errorMessage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.error)

            Text(errorMessage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.error.opacity(0.08))
        .cornerRadius(16)
    }

    private func scoreColor(for score: Double) -> Color {
        score >= 8.0 ? AppTheme.shared.current.colors.success :
        score >= 6.5 ? AppTheme.shared.current.colors.scoreColor :
                       AppTheme.shared.current.colors.warning
    }

    private func scoreGradient(for score: Double) -> LinearGradient {
        let color = scoreColor(for: score)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    private func criteria(from analysis: LocalAnalysis) -> [String: Double] {
        guard
            let data = analysis.criteriaJSON.data(using: .utf8),
            let dict = try? JSONDecoder().decode([String: Double].self, from: data)
        else {
            return [:]
        }
        return dict
    }

    private func metricHistory(for metricId: String) -> [ScorePoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let sorted = appState.recentAnalyses
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt < $1.createdAt }

        let points = sorted.compactMap { analysis -> ScorePoint? in
            let criteria = criteria(from: analysis)
            guard let value = criteria[metricId] else { return nil }
            return ScorePoint(id: analysis.id, timestamp: analysis.createdAt, value: value)
        }

        return Array(points.suffix(8))
    }

    private func consumeDeepDiveIntentIfNeeded() {
        guard appState.shouldOpenHomeDeepDive else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedAnalysisId = appState.homeDeepDiveAnalysisId
            selectedTab = .deepDive
        }
        appState.shouldOpenHomeDeepDive = false
        appState.homeDeepDiveAnalysisId = nil
    }

    private func openJourneyEditor(for date: Date) {
        let normalizedDay = SkinJourneyRepository.startOfDay(for: date)
        let today = SkinJourneyRepository.startOfDay(for: Date())
        guard normalizedDay <= today else { return }

        selectedJourneyDate = normalizedDay
        displayedJourneyMonth = Calendar.autoupdatingCurrent.date(
            from: Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: normalizedDay)
        ) ?? normalizedDay
        isJourneySheetPresented = true
    }

    private func toggleRoutineStep(_ stepID: String) {
        let existingLog = todayRoutineLog
        let existingStepIDs = Set(existingLog?.routineStepIDs ?? [])
        var updatedStepIDs = existingStepIDs
        let wasPendingCompletion = !existingStepIDs.contains(stepID)

        if updatedStepIDs.contains(stepID) {
            updatedStepIDs.remove(stepID)
        } else {
            updatedStepIDs.insert(stepID)
        }

        let activeSegmentStepIDs = Set(routinePlan.segment(for: selectedRoutineMoment).steps.map(\.id))
        let completedActiveStepCount = activeSegmentStepIDs.intersection(updatedStepIDs).count
        let completedActiveSegment = wasPendingCompletion
            && activeSegmentStepIDs.contains(stepID)
            && completedActiveStepCount == activeSegmentStepIDs.count
            && !activeSegmentStepIDs.isEmpty

        appState.saveSkinJourneyLog(
            date: Date(),
            routineStepIDs: SkinJourneyCatalog.sortedRoutineIDs(Array(updatedStepIDs)),
            treatmentIDs: existingLog?.treatmentIDs ?? [],
            skinStatusIDs: existingLog?.skinStatusIDs ?? [],
            note: existingLog?.note ?? ""
        )

        if completedActiveSegment {
            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
        }
    }

    private func toggleRoutineStatus(_ statusID: String) {
        let existingLog = todayRoutineLog
        var updatedStatuses = Set(existingLog?.skinStatusIDs ?? [])

        if updatedStatuses.contains(statusID) {
            updatedStatuses.remove(statusID)
        } else {
            updatedStatuses.insert(statusID)
        }

        appState.saveSkinJourneyLog(
            date: Date(),
            routineStepIDs: existingLog?.routineStepIDs ?? [],
            treatmentIDs: existingLog?.treatmentIDs ?? [],
            skinStatusIDs: SkinJourneyCatalog.sortedSkinStatusIDs(Array(updatedStatuses)),
            note: existingLog?.note ?? ""
        )
    }

#if DEBUG
    private func debugSessionCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DEBUG BACKEND SESSION")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                Spacer()
                Text(appState.debugHasStoredBackendSession ? "ATTACHED" : "MISSING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(appState.debugHasStoredBackendSession
                        ? AppTheme.shared.current.colors.accent
                        : AppTheme.shared.current.colors.error
                    )
            }

            debugRow("Endpoint", appState.debugBackendEndpoint)
            debugRow("Provider", appState.currentSession?.provider.rawValue ?? "none")
            debugRow("Remote User", appState.currentSession?.remoteUserId ?? "missing")
            debugRow("Stored Session", appState.debugHasStoredBackendSession ? "yes" : "no")

            if let error = appState.debugGuestBackendSessionError, !error.isEmpty {
                debugRow("Last Guest Error", error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(20)
    }

    private func debugMetadataCard(_ debugMetadata: LocalAnalysisDebugMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DEBUG SCAN METADATA")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                Spacer()
                Text(debugMetadata.source.userFacingLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
            }

            debugRow("Analysis Version", debugMetadata.analysisVersion ?? "unknown")
            if let referenceCatalogVersion = debugMetadata.referenceCatalogVersion {
                debugRow("Reference Catalog", referenceCatalogVersion)
            }
            if let verificationVerdict = debugMetadata.verificationVerdict {
                debugRow("Reference Audit", verificationVerdict.userFacingLabel)
            }
            if let baseScore = debugMetadata.baseScore {
                debugRow("Base Score", String(format: "%.1f", baseScore))
            }
            if let finalScore = debugMetadata.finalScore {
                debugRow("Final Score", String(format: "%.1f", finalScore))
            }
            if let adjustmentDelta = debugMetadata.adjustmentDelta, abs(adjustmentDelta) >= 0.05 {
                debugRow("Adjustment", String(format: "%+.1f", adjustmentDelta))
            }
            if let matchedReferenceIDs = debugMetadata.matchedReferenceIDs, !matchedReferenceIDs.isEmpty {
                debugRow("Matched Refs", matchedReferenceIDs.joined(separator: ", "))
            }
            if let adjustmentReason = debugMetadata.adjustmentReason, !adjustmentReason.isEmpty {
                debugRow("Audit Note", adjustmentReason)
            }
            debugRow("Predicted Band", debugMetadata.predictedBand ?? "unknown")

            if let model = debugMetadata.model {
                debugRow("Model", model)
            }

            debugRow("Conditions", debugConditionsText(debugMetadata.observedConditions))

            if let imageQualityStatus = debugMetadata.imageQualityStatus {
                let reasons = debugMetadata.imageQualityReasons.map(\.rawValue).joined(separator: ", ")
                let suffix = reasons.isEmpty ? "" : " (\(reasons))"
                debugRow("Image Quality", "\(imageQualityStatus.rawValue)\(suffix)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(20)
    }

    private func debugRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .frame(width: 108, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugConditionsText(_ conditions: SkinObservedConditions?) -> String {
        guard let conditions else { return "unknown" }

        let items: [(String, SkinConditionSeverity)] = [
            ("inflammation", conditions.activeInflammation),
            ("scarring", conditions.scarringPitting),
            ("texture", conditions.textureIrregularity),
            ("redness", conditions.rednessIrritation),
            ("dryness", conditions.drynessFlaking)
        ]

        let visible = items.compactMap { label, severity -> String? in
            severity == .none ? nil : "\(label): \(severity.rawValue)"
        }

        return visible.isEmpty ? "none" : visible.joined(separator: ", ")
    }
#endif
}

// MARK: - Skin Evolution Section

struct SkinEvolutionSection: View {
    let analyses: [LocalAnalysis]
    let scoreHistory: [ScorePoint]
    let isLocked: Bool
    let onUnlock: () -> Void
    let onScanTap: () -> Void

    // Chronologically sorted for display
    private var sorted: [LocalAnalysis] {
        analyses.sorted { $0.createdAt < $1.createdAt }
    }

    // Overall delta: latest minus first
    private var overallDelta: Double? {
        guard sorted.count >= 2 else { return nil }
        return sorted.last!.score - sorted.first!.score
    }

    // Trend label
    private var trendLabel: (icon: String, text: String, color: Color) {
        guard let delta = overallDelta else {
            return ("sparkles", "Start your journey", AppTheme.shared.current.colors.accent)
        }
        if delta > 0.25 {
            return ("arrow.up.right", "Improving", AppTheme.shared.current.colors.success)
        } else if delta < -0.25 {
            return ("arrow.down.right", "Declining", AppTheme.shared.current.colors.warning)
        } else {
            return ("minus", "Stable", AppTheme.shared.current.colors.scoreColor)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skin Evolution")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    if let delta = overallDelta {
                        let sign = delta >= 0 ? "+" : ""
                        Text("\(sign)\(String(format: "%.1f", delta)) since first scan")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(
                                delta > 0.25 ? AppTheme.shared.current.colors.success :
                                delta < -0.25 ? AppTheme.shared.current.colors.warning :
                                AppTheme.shared.current.colors.textSecondary
                            )
                    } else {
                        Text(analyses.isEmpty ? "No scans yet" : "One scan so far")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    }
                }
                Spacer()
                // Trend pill
                HStack(spacing: 5) {
                    Image(systemName: trendLabel.icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(trendLabel.text)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(trendLabel.color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(trendLabel.color.opacity(0.12))
                .cornerRadius(20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if isLocked {
                lockedContent
            } else if scoreHistory.count >= 2 {
                // ── Score Chart ───────────────────────────────────────────────
                let lo = scoreHistory.map(\.value).min() ?? 0
                let hi = scoreHistory.map(\.value).max() ?? 10
                let minV = Swift.max(0, lo - 1.0)
                let maxV = Swift.min(10, hi + 0.6)
                let domain: ClosedRange<Double> = minV < maxV ? minV...maxV : 0...10

                Chart {
                    ForEach(scoreHistory) { pt in
                        AreaMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(
                                colors: [AppTheme.shared.current.colors.accent.opacity(0.35),
                                         AppTheme.shared.current.colors.accent.opacity(0)],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        PointMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                            .foregroundStyle(AppTheme.shared.current.colors.accent)
                            .symbolSize(40)
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: Swift.min(4, scoreHistory.count))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(AppTheme.shared.current.colors.textSecondary)
                            .font(.system(size: 9))
                    }
                }
                .frame(height: 80)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            } else if analyses.isEmpty {
                // Placeholder wave shape for empty state
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.shared.current.colors.surfaceHigh)
                        .frame(height: 60)
                    Text("Your skin chart will appear after your first scan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Text("Scan again to see your evolution")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // ── Horizontal Scan Timeline ──────────────────────────────────────
            if !sorted.isEmpty {
                Divider()
                    .background(AppTheme.shared.current.colors.textPrimary.opacity(0.06))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Text("SCAN TIMELINE")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.3)
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, scan in
                            let prevScore: Double? = index > 0 ? sorted[index - 1].score : nil
                            let delta: Double? = prevScore.map { scan.score - $0 }
                            let isLatest = index == sorted.count - 1

                            HStack(spacing: 0) {
                                // Connector line (before the node, except for first)
                                if index > 0 {
                                    Rectangle()
                                        .fill(AppTheme.shared.current.colors.surfaceHigh)
                                        .frame(width: 24, height: 2)
                                        .padding(.top, 24)
                                }

                                // Scan card
                                ScanTimelineCard(
                                    scan: scan,
                                    delta: delta,
                                    isLatest: isLatest
                                )
                            }
                        }
                        // Trailing CTA to scan again
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(AppTheme.shared.current.colors.surfaceHigh)
                                .frame(width: 24, height: 2)
                                .padding(.top, 24)
                            Button(action: onScanTap) {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .strokeBorder(
                                                style: StrokeStyle(lineWidth: 2, dash: [4])
                                            )
                                            .foregroundColor(AppTheme.shared.current.colors.accent.opacity(0.5))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(AppTheme.shared.current.colors.accent)
                                    }
                                    Text("New\nScan")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AppTheme.shared.current.colors.accent)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 64)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                // Empty: single CTA button
                Button(action: onScanTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 14))
                        Text("Start Your Skin Journey")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.shared.current.colors.primaryGradient)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24)
            .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.07), lineWidth: 1))
        .shadow(color: AppTheme.shared.current.colors.textPrimary.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    private var lockedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.shared.current.colors.textPrimary.opacity(0.06))
                .padding(.horizontal, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.shared.current.colors.accentSoft.opacity(0.38),
                                AppTheme.shared.current.colors.accentSoft.opacity(0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: 180
                        )
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                VStack(spacing: 18) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.shared.current.colors.surfaceHigh)
                        .frame(height: 88)
                        .overlay(
                            VStack(alignment: .leading, spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.shared.current.colors.textPrimary.opacity(0.08))
                                    .frame(width: 110, height: 10)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.shared.current.colors.textPrimary.opacity(0.06))
                                    .frame(height: 44)
                                HStack(spacing: 8) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.shared.current.colors.surface)
                                            .frame(height: 8)
                                    }
                                }
                            }
                            .padding(14)
                        )

                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    index == 3
                                        ? AppTheme.shared.current.colors.accentSoft.opacity(0.55)
                                        : AppTheme.shared.current.colors.surfaceHigh
                                )
                                .frame(width: 68, height: 94)
                        }
                    }
                }
                .padding(16)
                .opacity(0.72)
                .blur(radius: 4)

                VStack(spacing: 12) {
                    Label("PRO", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                        .clipShape(Capsule())

                    Text("Unlock weekly progress history")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                    Text("Track your score over time, compare scan momentum, and revisit your full scan timeline.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)

                    Button(action: onUnlock) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Unlock PRO")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppTheme.shared.current.colors.accent)
                        .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 24)
            }
            .frame(height: 248)
            .clipped()
        }
    }
}

// MARK: - Scan Timeline Card

struct ScanTimelineCard: View {
    let scan: LocalAnalysis
    let delta: Double?
    let isLatest: Bool

    private var deltaColor: Color {
        guard let d = delta else { return AppTheme.shared.current.colors.textTertiary }
        return d > 0.05 ? AppTheme.shared.current.colors.success :
               d < -0.05 ? AppTheme.shared.current.colors.warning :
               AppTheme.shared.current.colors.textSecondary
    }

    private var deltaIcon: String {
        guard let d = delta else { return "" }
        return d > 0.05 ? "↑" : d < -0.05 ? "↓" : "→"
    }

    private var scoreColor: Color {
        scan.score >= 8.0 ? AppTheme.shared.current.colors.success :
        scan.score >= 6.5 ? AppTheme.shared.current.colors.scoreColor :
                            AppTheme.shared.current.colors.warning
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 6) {
            // Node circle
            ZStack {
                Circle()
                    .fill(isLatest
                          ? AppTheme.shared.current.colors.accent
                          : AppTheme.shared.current.colors.surfaceHigh)
                    .frame(width: 48, height: 48)
                    .shadow(
                        color: isLatest ? AppTheme.shared.current.colors.accentGlow.opacity(0.16) : .clear,
                        radius: 5,
                        x: 0,
                        y: 2
                    )
                Text(String(format: "%.1f", scan.score))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(isLatest ? AppTheme.shared.current.colors.bgPrimary : scoreColor)
            }

            // Date
            Text(ScanTimelineCard.dateFormatter.string(from: scan.createdAt))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textTertiary)

            // Delta badge
            if let d = delta {
                let sign = d >= 0 ? "+" : ""
                Text("\(deltaIcon)\(sign)\(String(format: "%.1f", d))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(deltaColor)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(deltaColor.opacity(0.12))
                    .cornerRadius(6)
            } else {
                Text("First")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(AppTheme.shared.current.colors.surfaceHigh)
                    .cornerRadius(6)
            }
        }
        .frame(width: 64)
    }
}

struct ScanStatTile: View {
    let eyebrow: String
    let icon: String
    let value: String
    let subtitle: String
    let footnote: String
    let accent: Color
    let accentSoft: Color
    let flameCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(1.2)
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 10)
                ZStack {
                    Circle()
                        .fill(accentSoft)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(accent)
                }
            }

            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            VStack(alignment: .leading, spacing: 8) {
                if let flameCount {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            Image(systemName: index < flameCount ? "flame.fill" : "flame")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(
                                    index < flameCount
                                        ? accent
                                        : AppTheme.shared.current.colors.textTertiary.opacity(0.6)
                                )
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle()
                                        .fill(
                                            index < flameCount
                                                ? accentSoft
                                                : AppTheme.shared.current.colors.surfaceHigh
                                        )
                                )
                        }
                    }
                }

                Text(footnote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [accentSoft, AppTheme.shared.current.colors.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Metric Detail Card

struct MetricDetailCard: View {
    let metric: SkinMetric
    let history: [ScorePoint]
    let onUnlock: () -> Void
    @State private var isReviewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                // Ring
                ZStack {
                    Circle().stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 3)
                        .frame(width: 42, height: 42)
                    if metric.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                    } else {
                        Circle()
                            .trim(from: 0, to: CGFloat(metric.score / 10.0))
                            .stroke(metricGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 42, height: 42)
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.1f", metric.score))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(scoreColor(for: metric.score))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(metric.isPremium
                                ? AppTheme.shared.current.colors.textTertiary
                                : AppTheme.shared.current.colors.accent)
                        Text(metric.id)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(metric.isPremium
                                ? AppTheme.shared.current.colors.textTertiary
                                : AppTheme.shared.current.colors.textPrimary)
                    }
                    Text(metricStatusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            metric.isPremium
                                ? AppTheme.shared.current.colors.accent
                                : scoreColor(for: metric.score)
                        )
                }
                Spacer()
                if metric.isPremium {
                    Label("PRO", systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            if metric.isPremium {
                // ── Locked content ────────────────────────────────────────────
                VStack(spacing: 0) {
                    Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.06))
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        AppTheme.shared.current.colors.accentSoft.opacity(0.18),
                                        AppTheme.shared.current.colors.accentSoft.opacity(0.06),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: 150
                                )
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                        // Blurred ghost of the real content
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.shared.current.colors.surfaceHigh).frame(height: 60)
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.shared.current.colors.textPrimary.opacity(0.06)).frame(height: 50)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.shared.current.colors.textPrimary.opacity(0.05)).frame(height: 50)
                            }
                        }
                        .padding(16)
                        .opacity(0.68)
                        .blur(radius: 4)

                        // CTA
                        Button(action: onUnlock) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill").font(.system(size: 12))
                                Text("Unlock PRO to see full analysis")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(AppTheme.shared.current.colors.accent)
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.shared.current.colors.accentGlow.opacity(0.16), radius: 6, x: 0, y: 3)
                        }
                    }
                    .frame(height: 120)
                    .clipped()
                }
            } else {
                // ── Full content ──────────────────────────────────────────────
                VStack(spacing: 0) {
                    Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.06))

                    // Chart — gets its own generous space
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REAL 30-DAY EVOLUTION")
                            .font(.system(size: 9, weight: .heavy)).kerning(1.1)
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                            .padding(.top, 14)
                            .padding(.horizontal, 16)

                        if history.count >= 2 {
                            let lo = history.map(\.value).min() ?? 0
                            let hi = history.map(\.value).max() ?? 10
                            let minV = Swift.max(0, lo - 0.5)
                            let maxV = Swift.min(10, hi + 0.5)
                            let domain: ClosedRange<Double> = minV < maxV ? minV...maxV : Swift.max(0, lo - 1.0)...Swift.min(10, hi + 1.0)

                            Chart {
                                ForEach(history) { pt in
                                    AreaMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                        .interpolationMethod(.monotone)
                                        .foregroundStyle(LinearGradient(
                                            colors: [AppTheme.shared.current.colors.accent.opacity(0.28),
                                                     AppTheme.shared.current.colors.accent.opacity(0)],
                                            startPoint: .top, endPoint: .bottom))
                                    LineMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                        .interpolationMethod(.monotone)
                                        .foregroundStyle(AppTheme.shared.current.colors.accent)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    PointMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                        .foregroundStyle(AppTheme.shared.current.colors.accent)
                                        .symbolSize(30)
                                }
                            }
                            .chartYScale(domain: domain)
                            .chartYAxis(.hidden)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: min(4, history.count))) { _ in
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        .foregroundStyle(AppTheme.shared.current.colors.textSecondary)
                                        .font(.system(size: 10))
                                }
                            }
                            // chart gets proper height and is strictly clipped — no bleed into cards below
                            .frame(height: 100)
                            .clipped()
                            .padding(.horizontal, 12)
                        } else {
                            Text("Need at least 2 real scans in the last 30 days to show evolution.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .padding(.bottom, 6)
                        }
                    }

                    criterionReviewContent
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(metric.isPremium
                    ? AppTheme.shared.current.colors.accent.opacity(0.18)
                    : AppTheme.shared.current.colors.textPrimary.opacity(0.07),
                        lineWidth: metric.isPremium ? 1.5 : 1)
        )
    }

    private var metricStatusLabel: String {
        if metric.isPremium {
            return "Unlock PRO"
        }
        return metric.insight?.status ?? "New scan needed"
    }

    private var criterionReviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Category Review", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
                Spacer()
                if metric.insight != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReviewExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isReviewExpanded ? "Show Less" : "Read Full Review")
                            Image(systemName: isReviewExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let insight = metric.insight {
                Text(insight.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .lineSpacing(4)
                    .lineLimit(isReviewExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if let concern = insight.negativeObservations.first {
                    InsightBulletRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Main watch-out",
                        text: concern,
                        tint: AppTheme.shared.current.colors.warning
                    )
                }

                if isReviewExpanded {
                    CriterionInsightList(
                        title: "What I noticed",
                        icon: "checkmark.seal.fill",
                        items: insight.positiveObservations,
                        tint: AppTheme.shared.current.colors.success
                    )
                    CriterionInsightList(
                        title: "Potential negatives",
                        icon: "exclamationmark.circle.fill",
                        items: insight.negativeObservations,
                        tint: AppTheme.shared.current.colors.warning
                    )
                    InsightBulletRow(
                        icon: "leaf.fill",
                        title: "Recommended focus",
                        text: insight.routineFocus,
                        tint: AppTheme.shared.current.colors.success
                    )
                }
            } else {
                Text("Detailed category review is available on new scans.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Run a fresh scan to see specific positives, potential negatives, and a focused routine recommendation for this category.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.accent.opacity(0.07))
        .cornerRadius(14)
    }

    private var metricGradient: LinearGradient {
        LinearGradient(colors: [AppTheme.shared.current.colors.accentGradientStart,
                                AppTheme.shared.current.colors.accentGradientEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func scoreColor(for score: Double) -> Color {
        score >= 8.0 ? AppTheme.shared.current.colors.success :
        score >= 6.5 ? AppTheme.shared.current.colors.scoreColor :
                       AppTheme.shared.current.colors.warning
    }

}

struct CriterionInsightList: View {
    let title: String
    let icon: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .cornerRadius(12)
    }
}

struct InsightBulletRow: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(tint)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Views

struct RecentAnalysisRow: View {
    let analysis: LocalAnalysis
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppTheme.shared.current.colors.surface)
                    .frame(width: 50, height: 50)
                    .overlay(Circle().stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 1))
                Text(String(format: "%.1f", analysis.score))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.scoreColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Skin Analysis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                Text(analysis.skinTypeDetected)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textTertiary)
        }
        .padding(14)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum HomeTab { case home, deepDive, routine }

private struct RoutineHubView: View {
    let plan: RoutineExperiencePlan
    @Binding var selectedMoment: RoutineMoment
    let completedStepIDs: Set<String>
    let selectedSkinStatusIDs: Set<String>
    let isProActive: Bool
    let onToggleStep: (String) -> Void
    let onToggleStatus: (String) -> Void
    let onEditLog: () -> Void
    let onUnlockPro: () -> Void
    let onScanTap: () -> Void

    private var activeSegment: RoutineSegmentPlan {
        plan.segment(for: selectedMoment)
    }

    private var nextSegment: RoutineSegmentPlan {
        plan.segment(for: selectedMoment.other)
    }

    private var completedCount: Int {
        plan.completedStepCount(using: completedStepIDs)
    }

    private var completionRatio: Double {
        guard plan.totalChecklistSteps > 0 else { return 0 }
        return Double(completedCount) / Double(plan.totalChecklistSteps)
    }

    private var currentSegmentCompletedCount: Int {
        activeSegment.steps.filter { completedStepIDs.contains($0.id) }.count
    }

    private var isCurrentSegmentComplete: Bool {
        currentSegmentCompletedCount == activeSegment.steps.count && !activeSegment.steps.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroCard
            focusCard
            checkInCard
            checklistCard
            nextUpCard
            momentumCard
            boosterSection
            weeklyLabSection
            Spacer(minLength: 80)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI ROUTINE")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(1.5)
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)

                    Text(plan.title)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                RoutineProgressRing(
                    progress: completionRatio,
                    completedCount: completedCount,
                    totalCount: plan.totalChecklistSteps,
                    isComplete: completionRatio >= 0.999
                )
            }

            HStack(spacing: 10) {
                ForEach(RoutineMoment.allCases) { moment in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedMoment = moment
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: moment.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(moment.displayName)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(selectedMoment == moment
                            ? AppTheme.shared.current.colors.bgPrimary
                            : AppTheme.shared.current.colors.textPrimary
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            selectedMoment == moment
                                ? AnyShapeStyle(AppTheme.shared.current.colors.primaryGradient)
                                : AnyShapeStyle(AppTheme.shared.current.colors.surfaceHigh.opacity(0.72))
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            Text(plan.sourceLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
        }
        .padding(20)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(AppTheme.shared.current.colors.surface)

                RoutineAuraView()
                    .frame(width: 180, height: 180)
                    .offset(x: 26, y: -18)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(plan.focusTint.color.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: plan.focusSymbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(plan.focusTint.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Focus")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(1.1)
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)

                    Text(plan.focusTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                }

                Spacer(minLength: 0)
            }

            Text(plan.focusMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Check-In")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text("Tap what your skin feels like right now. The routine adapts on the spot.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onEditLog) {
                    Text("Full Log")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(SkinJourneyCatalog.skinStatuses) { option in
                    RoutineSkinStatusChip(
                        option: option,
                        isSelected: selectedSkinStatusIDs.contains(option.id),
                        action: { onToggleStatus(option.id) }
                    )
                }
            }

            Text(plan.checkInMessage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(plan.focusTint.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeSegment.eyebrow)
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(1.3)
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    Text(activeSegment.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text(activeSegment.blurb)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(currentSegmentCompletedCount)/\(activeSegment.steps.count)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(plan.focusTint.color)
                    Text("done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }
            }

            VStack(spacing: 10) {
                ForEach(activeSegment.steps) { step in
                    RoutineChecklistStepRow(
                        step: step,
                        isCompleted: completedStepIDs.contains(step.id),
                        action: { onToggleStep(step.id) }
                    )
                }
            }

            if isCurrentSegmentComplete {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolEffect(.bounce, value: currentSegmentCompletedCount)
                    Text("Segment complete. Come back for the \(nextSegment.id.displayName.lowercased()) stack later.")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(plan.focusTint.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Text(activeSegment.footerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var nextUpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next Up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                Spacer()
                Label(nextSegment.id.shortLabel, systemImage: nextSegment.id.symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }

            Text(nextSegment.previewCopy)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(nextSegment.steps.prefix(4)), id: \.id) { step in
                        RoutineStepChip(title: step.title, tint: step.tint)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    private var momentumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Consistency")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text("Track how often you complete your routine and keep the habit going.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button(action: onScanTap) {
                    Text(plan.momentum.ctaTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.shared.current.colors.textPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                RoutineMiniStat(title: "Streak", value: plan.momentum.streakValue)
                RoutineMiniStat(title: "7-Day", value: plan.momentum.coverageValue)
                RoutineMiniStat(title: "Today", value: "\(completedCount)/\(plan.totalChecklistSteps)")
            }

            Text(plan.momentum.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var boosterSection: some View {
        if isProActive {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRO Boosters")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        Text("Optional extras when you want a little more lift than the core routine.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Label("Optional", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(AppTheme.shared.current.colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                VStack(spacing: 10) {
                    ForEach(plan.boosters) { step in
                        RoutineChecklistStepRow(
                            step: step,
                            isCompleted: completedStepIDs.contains(step.id),
                            action: { onToggleStep(step.id) }
                        )
                    }
                }

                Text("Boosters are bonus steps. They do not change your core completion target for the day.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(AppTheme.shared.current.colors.surface)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
            )
        } else {
            RoutineLockedPreviewCard(
                title: "PRO Boosters",
                subtitle: "Optional extra steps for recovery, texture, or breakout support.",
                previewSteps: plan.boosters,
                buttonTitle: "Unlock PRO",
                action: onUnlockPro
            )
        }
    }

    @ViewBuilder
    private var weeklyLabSection: some View {
        if isProActive {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Routine Lab")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        Text(plan.weeklyLab.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(plan.focusTint.color)
                    }
                    Spacer(minLength: 0)
                    Button(action: onScanTap) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.viewfinder")
                            Text(plan.weeklyLab.ctaTitle)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AppTheme.shared.current.colors.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    ForEach(plan.weeklyLab.stats) { stat in
                        RoutineMiniStat(title: stat.title, value: stat.value)
                    }
                }

                Text(plan.weeklyLab.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(AppTheme.shared.current.colors.surface)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
            )
        } else {
            RoutineLockedPreviewCard(
                title: "Routine Lab",
                subtitle: "Get weekly guidance, better scan timing, and a more tailored routine.",
                previewSteps: plan.weeklyLab.previewSteps,
                buttonTitle: "Unlock Routine Lab",
                action: onUnlockPro
            )
        }
    }
}

private struct RoutineAuraView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.shared.current.colors.accent.opacity(0.16))
                .frame(width: 156, height: 156)
                .blur(radius: 12)
                .scaleEffect(isAnimating ? 1.08 : 0.84)
                .opacity(isAnimating ? 0.82 : 0.42)

            Circle()
                .fill(AppTheme.shared.current.colors.accentGradientEnd.opacity(0.18))
                .frame(width: 108, height: 108)
                .blur(radius: 18)
                .offset(x: 24, y: -18)
                .scaleEffect(isAnimating ? 0.92 : 1.12)
                .opacity(isAnimating ? 0.65 : 0.42)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct RoutineProgressRing: View {
    let progress: Double
    let completedCount: Int
    let totalCount: Int
    let isComplete: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 8)
                .frame(width: 78, height: 78)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AppTheme.shared.current.colors.primaryGradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 78, height: 78)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)

            VStack(spacing: 1) {
                Text("\(completedCount)")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                Text(totalCount == 0 ? "today" : "of \(totalCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isComplete {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
                    .symbolEffect(.bounce, value: completedCount)
                    .offset(x: 4, y: -4)
            }
        }
    }
}

private struct RoutineSkinStatusChip: View {
    let option: SkinJourneyOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    private var tint: Color {
        switch option.id {
        case "dry":
            return AppTheme.shared.current.colors.scoreColor
        case "sensitive", "redness", "irritated":
            return AppTheme.shared.current.colors.warning
        case "breakout":
            return AppTheme.shared.current.colors.accent
        case "glowy":
            return AppTheme.shared.current.colors.accent
        default:
            return AppTheme.shared.current.colors.textPrimary
        }
    }

    private var iconName: String {
        switch option.id {
        case "dry":
            return "drop.fill"
        case "sensitive":
            return "hand.raised.fill"
        case "redness":
            return "thermometer.medium"
        case "breakout":
            return "dot.radiowaves.left.and.right"
        case "irritated":
            return "exclamationmark.circle.fill"
        case "glowy":
            return "sparkles"
        default:
            return "circle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isSelected ? AppTheme.shared.current.colors.bgPrimary : tint)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(isSelected ? tint : AppTheme.shared.current.colors.surfaceHigh.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(isPressed ? AppTheme.shared.current.motion.pressScale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
        }
        .buttonStyle(.plain)
        .pressEvents { pressed in
            isPressed = pressed
        }
        .onChange(of: isSelected) { oldValue, newValue in
            guard oldValue != newValue else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

private struct RoutineChecklistStepRow: View {
    let step: RoutineChecklistStepPlan
    let isCompleted: Bool
    let action: () -> Void

    @State private var glowPulse = false
    @State private var isPressed = false
    @State private var bounceTrigger = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(step.tint.color.opacity(glowPulse ? 0.18 : 0.08))
                        .frame(width: 46, height: 46)
                        .scaleEffect(glowPulse ? 1.18 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: glowPulse)

                    Image(systemName: step.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(step.tint.color)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(step.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                        if let badge = step.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(0.7)
                                .foregroundColor(step.tint.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(step.tint.color.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(step.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isCompleted ? AnyShapeStyle(step.tint.gradient) : AnyShapeStyle(AppTheme.shared.current.colors.textTertiary))
                    .symbolEffect(.bounce, value: bounceTrigger)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: isCompleted
                                ? [step.tint.color.opacity(0.18), step.tint.color.opacity(0.05)]
                                : [AppTheme.shared.current.colors.surface, AppTheme.shared.current.colors.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        isCompleted
                            ? step.tint.color.opacity(0.35)
                            : AppTheme.shared.current.colors.textPrimary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? AppTheme.shared.current.motion.pressScale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
        }
        .buttonStyle(.plain)
        .pressEvents { pressed in
            isPressed = pressed
        }
        .onChange(of: isCompleted) { oldValue, newValue in
            guard oldValue != newValue else { return }

            if newValue {
                bounceTrigger += 1
                glowPulse = true
                RoutineSoundPlayer.shared.playBoop()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    glowPulse = false
                }
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }
}

private struct RoutineMiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RoutineStepChip: View {
    let title: String
    let tint: RoutineTintStyle

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.72))
        .clipShape(Capsule())
    }
}

private struct RoutineLockedPreviewCard: View {
    let title: String
    let subtitle: String
    let previewSteps: [RoutineChecklistStepPlan]
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }
                Spacer(minLength: 0)
                Label("PRO", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                ForEach(previewSteps) { step in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(step.tint.color.opacity(0.12))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: step.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(step.tint.color)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            Text(step.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .opacity(0.55)
                }
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text(buttonTitle)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.shared.current.colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }
}

private enum RoutineMoment: String, CaseIterable, Identifiable {
    case morning
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning:
            return "Morning"
        case .evening:
            return "Night"
        }
    }

    var shortLabel: String {
        switch self {
        case .morning:
            return "AM"
        case .evening:
            return "PM"
        }
    }

    var symbolName: String {
        switch self {
        case .morning:
            return "sun.max.fill"
        case .evening:
            return "moon.stars.fill"
        }
    }

    var other: RoutineMoment {
        self == .morning ? .evening : .morning
    }

    static func current(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> RoutineMoment {
        calendar.component(.hour, from: date) < 16 ? .morning : .evening
    }
}

private enum RoutineFocusMode {
    case barrierReset
    case hydration
    case glow
    case clarify
    case tone
    case renew
    case starter
}

private enum RoutineTintStyle: Hashable {
    case focus
    case repair
    case bright
    case clarify
    case protect
    case premium

    var color: Color {
        switch self {
        case .focus:
            return AppTheme.shared.current.colors.accent
        case .repair:
            return AppTheme.shared.current.colors.scoreColor
        case .bright:
            return AppTheme.shared.current.colors.warning
        case .clarify:
            return AppTheme.shared.current.colors.accent
        case .protect:
            return AppTheme.shared.current.colors.textPrimary
        case .premium:
            return AppTheme.shared.current.colors.accentGradientEnd
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.9), AppTheme.shared.current.colors.accentGradientEnd.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct RoutineExperiencePlan {
    let title: String
    let subtitle: String
    let sourceLine: String
    let focusTitle: String
    let focusMessage: String
    let focusSymbolName: String
    let focusTint: RoutineTintStyle
    let segments: [RoutineSegmentPlan]
    let boosters: [RoutineChecklistStepPlan]
    let checkInMessage: String
    let momentum: RoutineMomentumPlan
    let weeklyLab: RoutineWeeklyLabPlan

    var totalChecklistSteps: Int {
        segments.reduce(0) { $0 + $1.steps.count }
    }

    func completedStepCount(using completedIDs: Set<String>) -> Int {
        segments
            .flatMap(\.steps)
            .filter { completedIDs.contains($0.id) }
            .count
    }

    func segment(for moment: RoutineMoment) -> RoutineSegmentPlan {
        segments.first(where: { $0.id == moment }) ?? segments[0]
    }
}

private struct RoutineSegmentPlan: Identifiable {
    let id: RoutineMoment
    let eyebrow: String
    let title: String
    let blurb: String
    let footerText: String
    let previewCopy: String
    let steps: [RoutineChecklistStepPlan]
}

private struct RoutineChecklistStepPlan: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: RoutineTintStyle
    let badge: String?
}

private struct RoutineMomentumPlan {
    let streakValue: String
    let coverageValue: String
    let message: String
    let ctaTitle: String
}

private struct RoutineWeeklyLabPlan {
    let title: String
    let message: String
    let stats: [RoutineStatItem]
    let ctaTitle: String
    let previewSteps: [RoutineChecklistStepPlan]
}

private struct RoutineStatItem: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

private enum RoutineExperiencePlanner {
    private static let irritationStatuses: Set<String> = ["sensitive", "redness", "irritated"]
    private static let breakoutStatuses: Set<String> = ["breakout"]
    private static let intenseTreatments: Set<String> = ["microneedling", "chemical_peel", "laser"]

    static func makePlan(
        latestAnalysis: LocalAnalysis?,
        recentAnalyses: [LocalAnalysis],
        latestCriteria: [String: Double],
        criterionInsights: [String: SkinCriterionInsight],
        userContext: SkinAnalysisUserContext?,
        recentLogs: [SkinJourneyLog],
        todayLog: SkinJourneyLog?,
        now: Date
    ) -> RoutineExperiencePlan {
        let goal = userContext?.goal ?? "Glow"
        let routineLevel = userContext?.routineLevel ?? "Basic"
        let todayStatuses = Set(todayLog?.skinStatusIDs ?? [])
        let lastThreeDaysLogs = recentLogs.filter { log in
            let cutoff = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: now) ?? now
            return log.dayStartAt >= dayStart(for: cutoff)
        }

        let recentIrritation = !todayStatuses.intersection(irritationStatuses).isEmpty
            || lastThreeDaysLogs.contains { !$0.skinStatusIDs.filter(irritationStatuses.contains).isEmpty }
            || lastThreeDaysLogs.contains { !$0.treatmentIDs.filter(intenseTreatments.contains).isEmpty }

        let recentBreakout = !todayStatuses.intersection(breakoutStatuses).isEmpty
            || lastThreeDaysLogs.contains { !$0.skinStatusIDs.filter(breakoutStatuses.contains).isEmpty }

        let weakestMetric = latestCriteria.min(by: { $0.value < $1.value })?.key
        let weakestMetricScore = weakestMetric.flatMap { latestCriteria[$0] }
        let focusMode = focusMode(
            goal: goal,
            weakestMetric: weakestMetric,
            weakestMetricScore: weakestMetricScore,
            recentIrritation: recentIrritation,
            recentBreakout: recentBreakout
        )

        let tint = tint(for: focusMode)
        let morningSteps = morningSteps(for: focusMode)
        let eveningSteps = eveningSteps(for: focusMode, routineLevel: routineLevel)
        let usedStepIDs = Set((morningSteps + eveningSteps).map(\.id))
        let boosters = boosterSteps(for: focusMode, excluding: usedStepIDs)

        let focusTitle = title(for: focusMode)
        let focusMessage = focusMessage(
            for: focusMode,
            weakestMetric: weakestMetric,
            criterionInsights: criterionInsights
        )

        let coverageCount = routineCoverageCount(in: recentLogs, days: 7, now: now)
        let streakCount = routineStreakCount(in: recentLogs, now: now)
        let scoreDelta = scoreDelta(from: recentAnalyses)

        let subtitle: String
        if latestAnalysis != nil {
            subtitle = "Built from your latest scan, \(goal.lowercased()) goal, and today's check-in."
        } else {
            subtitle = "Starter routine based on your \(goal.lowercased()) goal until you run a fresh scan."
        }

        let sourceLine = latestAnalysis == nil
            ? "Run a scan to personalize this routine."
            : "Updated from your latest scan and daily check-ins."

        let morningSegment = RoutineSegmentPlan(
            id: .morning,
            eyebrow: "AM STACK",
            title: "Morning Flow",
            blurb: "Simple daytime steps to protect your skin without making the routine feel heavy.",
            footerText: "Finish these before you start the day.",
            previewCopy: "Your evening routine is already lined up for later.",
            steps: morningSteps
        )

        let eveningSegment = RoutineSegmentPlan(
            id: .evening,
            eyebrow: "PM STACK",
            title: "Night Reset",
            blurb: "A short night routine focused on repair, recovery, and steady progress.",
            footerText: "Finish these before bed to stay consistent.",
            previewCopy: "Night is the best time for your more corrective steps.",
            steps: eveningSteps
        )

        let checkInMessage = checkInMessage(for: todayStatuses, focusMode: focusMode)
        let momentum = RoutineMomentumPlan(
            streakValue: streakCount == 0 ? "0d" : "\(streakCount)d",
            coverageValue: "\(coverageCount)/7",
            message: momentumMessage(
                streakCount: streakCount,
                coverageCount: coverageCount,
                completedToday: Set(todayLog?.routineStepIDs ?? []).count,
                totalToday: morningSteps.count + eveningSteps.count
            ),
            ctaTitle: latestAnalysis == nil ? "First Scan" : "New Scan"
        )

        let weakestLabel = weakestMetric.map(metricShortLabel(for:)) ?? "Routine"
        let weeklyStats: [RoutineStatItem] = [
            RoutineStatItem(title: "Focus", value: weakestLabel),
            RoutineStatItem(title: "7-Day", value: "\(coverageCount)d"),
            RoutineStatItem(title: "Trend", value: scoreDeltaLabel(scoreDelta))
        ]

        let weeklyLab = RoutineWeeklyLabPlan(
            title: weeklyLabTitle(for: focusMode, scoreDelta: scoreDelta, coverageCount: coverageCount),
            message: weeklyLabMessage(
                focusMode: focusMode,
                scoreDelta: scoreDelta,
                coverageCount: coverageCount,
                streakCount: streakCount
            ),
            stats: weeklyStats,
            ctaTitle: latestAnalysis == nil ? "Start With Scan" : "Scan Again",
            previewSteps: boosters
        )

        return RoutineExperiencePlan(
            title: focusTitle,
            subtitle: subtitle,
            sourceLine: sourceLine,
            focusTitle: focusTitle,
            focusMessage: focusMessage,
            focusSymbolName: symbolName(for: focusMode),
            focusTint: tint,
            segments: [morningSegment, eveningSegment],
            boosters: boosters,
            checkInMessage: checkInMessage,
            momentum: momentum,
            weeklyLab: weeklyLab
        )
    }

    private static func focusMode(
        goal: String,
        weakestMetric: String?,
        weakestMetricScore: Double?,
        recentIrritation: Bool,
        recentBreakout: Bool
    ) -> RoutineFocusMode {
        if recentIrritation {
            return .barrierReset
        }

        if recentBreakout && goal != "Anti-aging" {
            return .clarify
        }

        if let weakestMetric, let weakestMetricScore, weakestMetricScore < 6.2 {
            switch weakestMetric {
            case "Hydration":
                return .hydration
            case "Luminosity":
                return .glow
            case "Texture":
                return goal == "Acne Control" ? .clarify : .renew
            case "Uniformity":
                return .tone
            default:
                break
            }
        }

        switch goal {
        case "Hydration":
            return .hydration
        case "Glow":
            return .glow
        case "Acne Control":
            return .clarify
        case "Anti-aging":
            return .renew
        case "Even Tone":
            return .tone
        default:
            return .starter
        }
    }

    private static func title(for mode: RoutineFocusMode) -> String {
        switch mode {
        case .barrierReset:
            return "Barrier Reset"
        case .hydration:
            return "Hydration Lock-In"
        case .glow:
            return "Glow Builder"
        case .clarify:
            return "Clear Skin Flow"
        case .tone:
            return "Tone Control"
        case .renew:
            return "Renewal Rhythm"
        case .starter:
            return "Foundation First"
        }
    }

    private static func symbolName(for mode: RoutineFocusMode) -> String {
        switch mode {
        case .barrierReset:
            return "shield.lefthalf.filled"
        case .hydration:
            return "drop.fill"
        case .glow:
            return "sparkles"
        case .clarify:
            return "scope"
        case .tone:
            return "circle.lefthalf.filled"
        case .renew:
            return "clock.arrow.circlepath"
        case .starter:
            return "wand.and.stars"
        }
    }

    private static func tint(for mode: RoutineFocusMode) -> RoutineTintStyle {
        switch mode {
        case .barrierReset, .hydration, .starter:
            return .repair
        case .glow, .tone:
            return .bright
        case .clarify:
            return .clarify
        case .renew:
            return .protect
        }
    }

    private static func focusMessage(
        for mode: RoutineFocusMode,
        weakestMetric: String?,
        criterionInsights: [String: SkinCriterionInsight]
    ) -> String {
        if let weakestMetric,
           let insight = criterionInsights[weakestMetric],
           !insight.routineFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           mode != .barrierReset {
            return SkinJourneyLog.trimmedNote(insight.routineFocus, limit: 150)
        }

        switch mode {
        case .barrierReset:
            return "Your skin looks a little stressed, so today's routine keeps things calm and gentle."
        case .hydration:
            return "Focus on hydration first, then lock it in so your skin feels softer and more comfortable."
        case .glow:
            return "Brighten in the morning and protect your results through the day."
        case .clarify:
            return "Keep the routine clear and consistent so you can manage breakouts without over-drying your skin."
        case .tone:
            return "Even tone improves best with brightening, protection, and a calm barrier."
        case .renew:
            return "Use your more corrective steps at night and keep daytime protection strong."
        case .starter:
            return "Keep it simple for now. A short routine is easier to stick with every day."
        }
    }

    private static func morningSteps(for mode: RoutineFocusMode) -> [RoutineChecklistStepPlan] {
        let focusID: String
        let focusTint: RoutineTintStyle

        switch mode {
        case .barrierReset, .hydration, .starter:
            focusID = "hydrating_serum"
            focusTint = .repair
        case .glow, .tone, .renew:
            focusID = "vitamin_c"
            focusTint = .bright
        case .clarify:
            focusID = "niacinamide"
            focusTint = .clarify
        }

        return [
            step(id: "cleanser", tint: .focus),
            step(id: focusID, tint: focusTint),
            step(id: "moisturizer", tint: .repair),
            step(id: "spf", tint: .bright)
        ]
    }

    private static func eveningSteps(for mode: RoutineFocusMode, routineLevel: String) -> [RoutineChecklistStepPlan] {
        let wantsGentlerActive = routineLevel == "No routine" || routineLevel == "Beginner"
        let activeID: String
        let activeTint: RoutineTintStyle

        switch mode {
        case .barrierReset, .hydration, .starter:
            activeID = "overnight_mask"
            activeTint = .repair
        case .glow:
            activeID = "peptide_serum"
            activeTint = .premium
        case .tone:
            activeID = wantsGentlerActive ? "niacinamide" : "azelaic_acid"
            activeTint = wantsGentlerActive ? .clarify : .bright
        case .clarify:
            activeID = wantsGentlerActive ? "spot_treatment" : "salicylic_acid"
            activeTint = .clarify
        case .renew:
            activeID = wantsGentlerActive ? "peptide_serum" : "retinoid"
            activeTint = wantsGentlerActive ? .premium : .protect
        }

        return [
            step(id: "night_cleanse", tint: .focus),
            step(id: activeID, tint: activeTint),
            step(id: "barrier_cream", tint: .repair)
        ]
    }

    private static func boosterSteps(
        for mode: RoutineFocusMode,
        excluding usedStepIDs: Set<String>
    ) -> [RoutineChecklistStepPlan] {
        let candidates: [String]

        switch mode {
        case .barrierReset, .hydration:
            candidates = ["peptide_serum", "overnight_mask", "spot_treatment"]
        case .glow:
            candidates = ["overnight_mask", "peptide_serum", "spot_treatment"]
        case .clarify:
            candidates = ["spot_treatment", "overnight_mask", "peptide_serum"]
        case .tone:
            candidates = ["peptide_serum", "overnight_mask", "spot_treatment"]
        case .renew:
            candidates = ["peptide_serum", "overnight_mask", "spot_treatment"]
        case .starter:
            candidates = ["overnight_mask", "peptide_serum", "spot_treatment"]
        }

        return candidates
            .filter { !usedStepIDs.contains($0) }
            .prefix(2)
            .map { step(id: $0, tint: .premium, badge: "PRO") }
    }

    private static func checkInMessage(for statuses: Set<String>, focusMode: RoutineFocusMode) -> String {
        if statuses.isEmpty {
            return "No check-in yet. Tap how your skin feels and your routine will adjust."
        }

        if !statuses.intersection(irritationStatuses).isEmpty {
            return "Your skin seems sensitive today, so the routine is focusing on calming and barrier support."
        }

        if statuses.contains("breakout") {
            return "Breakout noted. The routine keeps pore care in, but still protects your skin barrier."
        }

        if statuses.contains("dry") {
            return "Dryness noted. Hydration and seal-in steps are doing more of the work today."
        }

        if statuses.contains("glowy") {
            return "Glow is already showing. Today's job is to protect it instead of over-treating."
        }

        switch focusMode {
        case .clarify:
            return "Today's routine is keeping things clear without being too harsh."
        case .renew:
            return "Your routine still includes renewal steps, but it stays simple enough to follow."
        default:
            return "Check-in saved. Your routine has been adjusted for today."
        }
    }

    private static func momentumMessage(
        streakCount: Int,
        coverageCount: Int,
        completedToday: Int,
        totalToday: Int
    ) -> String {
        if totalToday > 0 && completedToday == totalToday {
            return "Nice work. You've finished today's routine."
        }

        if coverageCount >= 5 {
            return "You're building a solid routine. Keep it going and rescan soon to track progress."
        }

        if streakCount >= 2 {
            return "You're getting consistent. Keep completing your routine to build the streak."
        }

        return "Complete a few steps today to start building consistency."
    }

    private static func weeklyLabTitle(
        for mode: RoutineFocusMode,
        scoreDelta: Double?,
        coverageCount: Int
    ) -> String {
        if let scoreDelta, scoreDelta >= 0.25 {
            return "Protect The Gain"
        }

        if coverageCount < 3 {
            return "Consistency Sprint"
        }

        switch mode {
        case .barrierReset:
            return "Calm Window"
        case .clarify:
            return "Clearer Signal"
        default:
            return "Sharper Trend"
        }
    }

    private static func weeklyLabMessage(
        focusMode: RoutineFocusMode,
        scoreDelta: Double?,
        coverageCount: Int,
        streakCount: Int
    ) -> String {
        if let scoreDelta, scoreDelta >= 0.25 {
            return "Your latest score moved \(String(format: "%+.1f", scoreDelta)). Keep this routine steady for a few more days before changing anything."
        }

        if coverageCount < 3 {
            return "Aim for three routine days this week, then scan again to get a clearer before-and-after."
        }

        if focusMode == .barrierReset {
            return "Keep things gentle for the next 48 hours. If your skin feels calmer, that's a good time to scan again."
        }

        if streakCount >= 4 {
            return "Your streak is strong enough to show a pattern. Stay consistent and rescan while the routine is still fresh."
        }

        return "Stay consistent a little longer, then rescan to see how your routine is working."
    }

    private static func scoreDelta(from recentAnalyses: [LocalAnalysis]) -> Double? {
        guard recentAnalyses.count >= 2 else { return nil }
        return recentAnalyses[0].score - recentAnalyses[1].score
    }

    private static func scoreDeltaLabel(_ delta: Double?) -> String {
        guard let delta else { return "Base" }
        return String(format: "%+.1f", delta)
    }

    private static func metricShortLabel(for metric: String) -> String {
        switch metric {
        case "Hydration":
            return "Hydrate"
        case "Luminosity":
            return "Glow"
        case "Texture":
            return "Smooth"
        case "Uniformity":
            return "Tone"
        default:
            return metric
        }
    }

    private static func routineCoverageCount(in logs: [SkinJourneyLog], days: Int, now: Date) -> Int {
        let cutoff = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return logs
            .filter { $0.dayStartAt >= dayStart(for: cutoff) && !$0.routineStepIDs.isEmpty }
            .count
    }

    private static func routineStreakCount(in logs: [SkinJourneyLog], now: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let logByDay = Dictionary(uniqueKeysWithValues: logs.map { ($0.dayKey, $0) })
        var streak = 0

        for dayOffset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { break }
            let key = dayKey(for: date)
            guard let log = logByDay[key], !log.routineStepIDs.isEmpty else { break }
            streak += 1
        }

        return streak
    }

    private static func dayStart(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func dayKey(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dayStart(for: date))
    }

    private static func step(id: String, tint: RoutineTintStyle, badge: String? = nil) -> RoutineChecklistStepPlan {
        RoutineChecklistStepPlan(
            id: id,
            title: SkinJourneyCatalog.title(for: id),
            detail: detail(for: id),
            icon: icon(for: id),
            tint: tint,
            badge: badge
        )
    }

    private static func detail(for id: String) -> String {
        switch id {
        case "cleanser":
            return "Clear the canvas so the rest of the routine actually lands."
        case "night_cleanse":
            return "Wash off the day so the repair steps hit clean skin."
        case "hydrating_serum":
            return "Water-first layer for softness, bounce, and less tightness."
        case "vitamin_c":
            return "Morning brightening support so glow and tone do not get undone."
        case "niacinamide":
            return "Helps calm oil, pores, and post-breakout noise without much drama."
        case "moisturizer":
            return "Seal hydration and keep the barrier from leaking all day."
        case "spf":
            return "Protect your skin during the day and help maintain your results."
        case "peptide_serum":
            return "Smoother, bouncier finish without hitting the skin too hard."
        case "retinoid":
            return "Long-game texture and firmness support for the night slot."
        case "salicylic_acid":
            return "Night pore sweep to keep buildup moving instead of sitting."
        case "azelaic_acid":
            return "Tone-calming step for marks, redness, and uneven patches."
        case "spot_treatment":
            return "Targets the breakout instead of drying out everything else."
        case "barrier_cream":
            return "Comfort layer that helps skin stay calmer by morning."
        case "overnight_mask":
            return "Extra cushion when the skin feels dry, stressed, or depleted."
        default:
            return "Small step, clear purpose, low friction."
        }
    }

    private static func icon(for id: String) -> String {
        switch id {
        case "cleanser", "night_cleanse":
            return "drop.circle.fill"
        case "hydrating_serum":
            return "drop.fill"
        case "vitamin_c":
            return "sun.max.fill"
        case "niacinamide":
            return "sparkles"
        case "moisturizer", "barrier_cream":
            return "shield.lefthalf.filled"
        case "spf":
            return "sun.max.circle.fill"
        case "peptide_serum":
            return "waveform.path.ecg"
        case "retinoid":
            return "moon.stars.fill"
        case "salicylic_acid":
            return "scope"
        case "azelaic_acid":
            return "circle.lefthalf.filled"
        case "spot_treatment":
            return "sparkle.magnifyingglass"
        case "overnight_mask":
            return "bed.double.fill"
        default:
            return "checkmark.circle.fill"
        }
    }
}

private final class RoutineSoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = RoutineSoundPlayer()

    private static let boopBase64 = """
    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
    """

    private let audioData: Data?
    private var activePlayers: [AVAudioPlayer] = []
    private var didConfigureAudioSession = false

    override init() {
        self.audioData = Data(base64Encoded: Self.boopBase64, options: .ignoreUnknownCharacters)
        super.init()
    }

    func playBoop(rate: Float = 1.0, volume: Float = 0.22) {
        guard let audioData else { return }

        configureAudioSessionIfNeeded()

        do {
            let player = try AVAudioPlayer(data: audioData)
            player.enableRate = true
            player.rate = rate
            player.volume = volume
            player.delegate = self
            player.prepareToPlay()
            activePlayers.append(player)
            player.play()
        } catch {
            return
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        activePlayers.removeAll { $0 === player }
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        didConfigureAudioSession = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            return
        }
    }
}
