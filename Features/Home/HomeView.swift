import SwiftUI
import Charts

// MARK: - Models

struct SkinMetric: Identifiable {
    let id: String
    let icon: String
    let score: Double
    let aiInsight: String
    let routineFix: String
    let isPremium: Bool
}

struct ScorePoint: Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: HomeTab = .home
    @State private var orbScale: CGFloat = 1.0
    @State private var selectedAnalysisId: String? = nil

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

    // Build score history from real analyses (chronological)
    private var scoreHistory: [ScorePoint] {
        let sorted = appState.recentAnalyses
            .sorted { $0.createdAt < $1.createdAt }
        return Array(sorted.suffix(8)).map { analysis in
            ScorePoint(id: analysis.id, timestamp: analysis.createdAt, value: analysis.score)
        }
    }

    // ── Metric definitions (free vs premium, with AI text) ───────────────────
    private var metrics: [SkinMetric] {
        guard activeAnalysis != nil else { return [] }   // no data yet = no metrics
        let allDefs: [(id: String, icon: String, isPremium: Bool)] = [
            ("Hydration",  "💧", false),
            ("Luminosity", "✨", false),
            ("Texture",    "🧬", false),
            ("Uniformity", "🎨", true),
            ("Elasticity", "🧪", true),
            ("Pores",      "🔬", true),
            ("Oiliness",   "💎", true),
            ("UV Damage",  "☀️", true),
        ]
        return allDefs.map { def in
            let score = latestCriteria[def.id] ?? 0.0   // 0 = truly no data
            return SkinMetric(id: def.id, icon: def.icon, score: score,
                              aiInsight: insightText(for: def.id, score: score),
                              routineFix: routineFixText(for: def.id, score: score),
                              isPremium: def.isPremium)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()

            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 140, y: -120)
                .scaleEffect(orbScale)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { orbScale = 1.3 }
                }

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Skin")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        Text("Track your skin's progress")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        homeTabPill(label: "Home",      tab: .home)
                        homeTabPill(label: "Deep Dive", tab: .deepDive)
                    }
                    .padding(4)
                    .background(AppTheme.shared.current.colors.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.07), lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.05))

                if selectedTab == .home {
                    homeContent.transition(.opacity)
                } else {
                    deepDiveContent.transition(.opacity)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.refreshRecentAnalyses()
            consumeDeepDiveIntentIfNeeded()
        }
        .onChange(of: appState.shouldOpenHomeDeepDive) { _ in
            consumeDeepDiveIntentIfNeeded()
        }
        .onChange(of: appState.recentAnalyses.map(\.id)) { ids in
            if let selectedAnalysisId, !ids.contains(selectedAnalysisId) {
                self.selectedAnalysisId = nil
            }
        }
    }

    // MARK: - Tab Pill

    @ViewBuilder
    private func homeTabPill(label: String, tab: HomeTab) -> some View {
        let sel = selectedTab == tab
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(sel ? AppTheme.shared.current.colors.bgPrimary : AppTheme.shared.current.colors.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(sel ? AppTheme.shared.current.colors.textPrimary : Color.clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Home Tab

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Main scan CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    appState.navigate(to: .upload)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(AppTheme.shared.current.colors.primaryGradient)
                            .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 20, x: 0, y: 10)
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 44, weight: .thin))
                                .foregroundColor(.black.opacity(0.75))
                            VStack(spacing: 4) {
                                Text("Scan Your Skin")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundColor(.black)
                                Text("Get your AI Skin Score in 10 seconds")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.55))
                            }
                        }
                        .padding(.vertical, 32)
                    }
                }
                .buttonStyle(ScaleButtonStyle())

                if !appState.recentAnalyses.isEmpty, let latest = mostRecentAnalysis {
                    // Score strip → opens Deep Dive
                    HStack(spacing: 14) {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Latest Score")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            Text(latest.summary)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = .deepDive }
                        } label: {
                            Text("Deep Dive →")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(AppTheme.shared.current.colors.accent)
                                .clipShape(Capsule())
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
                        onScanTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                appState.navigate(to: .upload)
                            }
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
                        onScanTap: { appState.navigate(to: .upload) }
                    )
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
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
                        Text("Your real metrics, AI analysis,\nand routine fixes will appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                        PrimaryButton("Scan My Skin Now") {
                            appState.navigate(to: .upload)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.shared.current.colors.surface)
                    .cornerRadius(24)

                } else {
                    // ── Free Metrics ──────────────────────────────────────────
                    HStack {
                        Text("INCLUDED").font(.system(size: 10, weight: .heavy)).kerning(1.4)
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(metrics.filter { !$0.isPremium }) { metric in
                        MetricDetailCard(
                            metric: metric,
                            history: metricHistory(for: metric.id),
                            onUnlock: { appState.navigate(to: .paywall) }
                        )
                    }

                    // ── Premium Metrics ───────────────────────────────────────
                    HStack {
                        Text("PRO").font(.system(size: 10, weight: .heavy)).kerning(1.4)
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                        Spacer()
                        Button { appState.navigate(to: .paywall) } label: {
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

                    ForEach(metrics.filter { $0.isPremium }) { metric in
                        MetricDetailCard(
                            metric: metric,
                            history: [],
                            onUnlock: { appState.navigate(to: .paywall) }
                        )
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
                    if let a = mostRecentAnalysis {
                        Text(a.skinTypeDetected)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                    }
                }
                Spacer()
                Button { appState.navigate(to: .upload) } label: {
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
                    .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 10, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.06)).padding(.horizontal, 20)

            // Metric bars
            VStack(spacing: 11) {
                ForEach(metrics) { metric in
                    HStack(spacing: 10) {
                        Text(metric.icon).font(.system(size: 14)).frame(width: 20)

                        Text(metric.id)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(metric.isPremium
                                ? AppTheme.shared.current.colors.textTertiary
                                : AppTheme.shared.current.colors.textPrimary)
                            .frame(width: 84, alignment: .leading)

                        if metric.isPremium {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4).fill(AppTheme.shared.current.colors.surfaceHigh).frame(height: 7)
                                RoundedRectangle(cornerRadius: 4).fill(AppTheme.shared.current.colors.accent.opacity(0.25)).frame(width: 48, height: 7).blur(radius: 2)
                            }
                            Text("PRO")
                                .font(.system(size: 8, weight: .heavy)).kerning(0.5)
                                .foregroundColor(AppTheme.shared.current.colors.accent)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                                .cornerRadius(4)
                                .frame(width: 32)
                        } else {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(AppTheme.shared.current.colors.surfaceHigh).frame(height: 7)
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

            // Score history chart — only if ≥2 scans
            if scoreHistory.count >= 2 {
                Divider().background(AppTheme.shared.current.colors.textPrimary.opacity(0.06)).padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("REAL SCORE HISTORY (\(scoreHistory.count) scans)")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.2)
                        .foregroundColor(AppTheme.shared.current.colors.textTertiary)

                    Chart {
                        let history = scoreHistory
                        ForEach(history) { pt in
                            AreaMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(LinearGradient(
                                    colors: [AppTheme.shared.current.colors.accent.opacity(0.3),
                                             AppTheme.shared.current.colors.accent.opacity(0)],
                                    startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(AppTheme.shared.current.colors.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(x: .value("Date", pt.timestamp), y: .value("Score", pt.value))
                                .foregroundStyle(AppTheme.shared.current.colors.accent)
                                .symbolSize(28)
                        }
                    }
                    .chartYScale(domain: {
                        let lo = scoreHistory.map(\.value).min() ?? 0
                        let hi = scoreHistory.map(\.value).max() ?? 10
                        return Swift.max(0, lo - 1.0)...(Swift.min(10, hi + 0.6))
                    }())
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(4, scoreHistory.count))) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(AppTheme.shared.current.colors.textSecondary)
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 70)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 12)
            }
        }
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24)
            .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.06), lineWidth: 1))
        .shadow(color: AppTheme.shared.current.colors.textPrimary.opacity(0.04), radius: 16, x: 0, y: 6)
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

    private func insightText(for metricId: String, score: Double) -> String {
        let level: String
        if score >= 8.0 {
            level = "looks strong with minimal visible concerns"
        } else if score >= 6.5 {
            level = "shows mild visible concerns"
        } else if score >= 5.0 {
            level = "shows moderate visible concerns"
        } else {
            level = "shows pronounced visible concerns"
        }
        return "Latest scan suggests \(metricId.lowercased()) \(level)."
    }

    private func routineFixText(for metricId: String, score: Double) -> String {
        let intensity: String
        if score >= 8.0 {
            intensity = "Maintain current routine and monitor weekly."
        } else if score >= 6.5 {
            intensity = "Add one targeted product and reassess in 2 weeks."
        } else if score >= 5.0 {
            intensity = "Use a focused routine daily and reassess after 14 days."
        } else {
            intensity = "Prioritize gentle barrier repair and seek professional guidance if persistent."
        }

        let focus: String
        switch metricId {
        case "Hydration":
            focus = "Use hydrating serum on damp skin, then seal with moisturizer."
        case "Luminosity":
            focus = "Use gentle chemical exfoliation 1-2x per week and daily sunscreen."
        case "Texture":
            focus = "Use niacinamide and consistent nighttime cleansing."
        case "Uniformity":
            focus = "Use vitamin C in the morning and broad-spectrum SPF 50."
        case "Elasticity":
            focus = "Use peptide moisturizer and low-strength retinoid at night."
        case "Pores":
            focus = "Use salicylic acid on T-zone and avoid heavy occlusive products."
        case "Oiliness":
            focus = "Use lightweight gel moisturizer and niacinamide."
        case "UV Damage":
            focus = "Apply SPF 50 daily and reapply every 2 hours outdoors."
        default:
            focus = "Keep a consistent basic routine and track changes per scan."
        }
        return "\(focus) \(intensity)"
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
}

// MARK: - Skin Evolution Section

struct SkinEvolutionSection: View {
    let analyses: [LocalAnalysis]
    let scoreHistory: [ScorePoint]
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

            // ── Score Chart ───────────────────────────────────────────────────
            if scoreHistory.count >= 2 {
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
                    .shadow(color: isLatest ? AppTheme.shared.current.colors.accentGlow : .clear,
                            radius: 8, x: 0, y: 3)
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

// MARK: - Metric Detail Card

struct MetricDetailCard: View {
    let metric: SkinMetric
    let history: [ScorePoint]
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                // Ring
                ZStack {
                    Circle().stroke(AppTheme.shared.current.colors.surfaceHigh, lineWidth: 3)
                        .frame(width: 42, height: 42)
                    Circle()
                        .trim(from: 0, to: CGFloat(metric.score / 10.0))
                        .stroke(metricGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 42, height: 42)
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.1f", metric.score))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(scoreColor(for: metric.score))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(metric.icon) \(metric.id)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(metric.isPremium
                            ? AppTheme.shared.current.colors.textTertiary
                            : AppTheme.shared.current.colors.textPrimary)
                    Text(statusLabel(for: metric.score))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(scoreColor(for: metric.score))
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
                        // Blurred ghost of the real content
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.shared.current.colors.surfaceHigh).frame(height: 60)
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.shared.current.colors.accent.opacity(0.1)).frame(height: 50)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.shared.current.colors.success.opacity(0.1)).frame(height: 50)
                            }
                        }
                        .padding(16)
                        .blur(radius: 8)

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
                            .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 10, x: 0, y: 4)
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

                    // Insight + Fix — full width below chart
                    VStack(spacing: 10) {
                        // AI Analysis
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(AppTheme.shared.current.colors.accent.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppTheme.shared.current.colors.accent)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI Analysis")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.shared.current.colors.accent)
                                Text(metric.aiInsight)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(4)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.shared.current.colors.accent.opacity(0.07))
                        .cornerRadius(14)

                        // Routine Fix
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(AppTheme.shared.current.colors.success.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(AppTheme.shared.current.colors.success)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Routine Fix")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.shared.current.colors.success)
                                Text(metric.routineFix)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(4)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.shared.current.colors.success.opacity(0.07))
                        .cornerRadius(14)
                    }
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

    private func statusLabel(for score: Double) -> String {
        score >= 8.5 ? "Excellent" : score >= 7.5 ? "Good" :
        score >= 6.5 ? "Average"  : "Needs Attention"
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

enum HomeTab { case home, deepDive }
