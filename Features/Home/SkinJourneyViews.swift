import SwiftUI
import UIKit

struct SkinJourneySection: View {
    let logs: [SkinJourneyLog]
    let analysisEntries: [AnalysisCalendarEntry]
    let latestAnalysis: LocalAnalysis?
    let latestCriteria: [String: Double]
    let isLocked: Bool
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let onUnlock: () -> Void
    let onLogToday: () -> Void
    let onEditSelectedDay: () -> Void
    let onLogSelectedDay: () -> Void

    private let calendar = Calendar.autoupdatingCurrent

    private var today: Date {
        SkinJourneyCalendar.startOfDay(for: Date())
    }

    private var currentMonth: Date {
        SkinJourneyCalendar.startOfMonth(for: today)
    }

    private var selectedLog: SkinJourneyLog? {
        log(for: selectedDate)
    }

    private var selectedAnalysisEntry: AnalysisCalendarEntry? {
        analysisEntry(for: selectedDate)
    }

    private var last14DaysLogs: [SkinJourneyLog] {
        let cutoff = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        return logs.filter { $0.dayStartAt >= cutoff }
    }

    private var last7DayCoverage: Int {
        let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let keys = logs
            .filter { $0.dayStartAt >= cutoff }
            .map(\.dayKey)
        return Set(keys).count
    }

    private var suggestionState: SkinJourneySuggestionState {
        SkinJourneyPlanner.makeSuggestion(
            latestAnalysis: latestAnalysis,
            latestCriteria: latestCriteria,
            recentLogs: last14DaysLogs,
            last7DayCoverage: last7DayCoverage
        )
    }

    private var monthTitle: String {
        SkinJourneyFormatters.month.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = max(calendar.firstWeekday - 1, 0)
        guard first < symbols.count else { return symbols }
        let prefix = symbols[first...]
        let suffix = symbols[..<first]
        return Array(prefix + suffix)
    }

    private var visibleDays: [Date] {
        SkinJourneyCalendar.visibleDays(for: displayedMonth, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLocked {
                lockedContent
            } else {
                monthPicker
                weekdayHeader
                calendarGrid
                selectedDaySummary
                if let banner = suggestionState.bannerMessage {
                    consistencyBanner(text: banner)
                }
                suggestionCard
            }
        }
        .padding(18)
        .background(AppTheme.shared.current.colors.surface)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.07), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skin Journey")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                Text(isLocked
                    ? "Unlock routines, treatments, and personalized journey suggestions."
                    : "Track routines, treatments, and how your skin feels.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }
            Spacer()
            if isLocked {
                Label("PRO", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.shared.current.colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Button(action: onLogToday) {
                    Text("Log Today")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.shared.current.colors.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var lockedContent: some View {
        ZStack {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.shared.current.colors.surfaceHigh)
                    .frame(height: 48)
                    .overlay(
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.shared.current.colors.surface)
                                .frame(width: 34, height: 34)
                            Spacer()
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.shared.current.colors.surface)
                                .frame(width: 34, height: 34)
                        }
                        .padding(.horizontal, 12)
                    )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(0..<21, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(index.isMultiple(of: 5)
                                ? AppTheme.shared.current.colors.accent.opacity(0.16)
                                : AppTheme.shared.current.colors.surfaceHigh
                            )
                            .frame(height: 54)
                    }
                }

                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.shared.current.colors.surfaceHigh)
                    .frame(height: 120)
                    .overlay(
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.shared.current.colors.accent.opacity(0.10))
                                .frame(width: 150, height: 10)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.shared.current.colors.surface)
                                .frame(height: 18)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.shared.current.colors.surface)
                                .frame(height: 18)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.shared.current.colors.surface)
                                .frame(width: 180, height: 18)
                        }
                        .padding(18)
                    )
            }
            .opacity(0.72)
            .blur(radius: 4)

            VStack(spacing: 12) {
                Text("Unlock personalized journey tracking")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                Text("Save routines, track treatments, and get tailored suggestions based on your latest scans.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)

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
            .padding(.horizontal, 12)
        }
        .frame(height: 360)
        .clipped()
    }

    private var monthPicker: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.shared.current.colors.surfaceHigh)
                    .clipShape(Circle())
            }

            Spacer()

            Text(monthTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canMoveForward ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.shared.current.colors.surfaceHigh)
                    .clipShape(Circle())
            }
            .disabled(!canMoveForward)
        }
    }

    private var canMoveForward: Bool {
        displayedMonth < currentMonth
    }

    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(visibleDays, id: \.self) { day in
                calendarDayCell(for: day)
            }
        }
    }

    @ViewBuilder
    private func calendarDayCell(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isCurrentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isFutureDay = day > today
        let isFutureMonth = SkinJourneyCalendar.startOfMonth(for: day) > currentMonth
        let log = log(for: day)
        let analysisEntry = analysisEntry(for: day)
        let isDisabled = isFutureMonth

        Button {
            guard !isDisabled else { return }
            handleDayTap(day)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 13, weight: isSelected ? .heavy : .semibold))
                        .foregroundColor(dayTextColor(isSelected: isSelected, isCurrentMonth: isCurrentMonth, isFutureDay: isFutureDay))
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 3) {
                        dot(color: AppTheme.shared.current.colors.accent, isVisible: !(log?.routineStepIDs.isEmpty ?? true))
                        dot(color: AppTheme.shared.current.colors.warning, isVisible: !(log?.treatmentIDs.isEmpty ?? true))
                        dot(color: AppTheme.shared.current.colors.scoreColor, isVisible: !(log?.skinStatusIDs.isEmpty ?? true))
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)

                if analysisEntry != nil {
                    analysisBadge
                        .offset(x: 4, y: -4)
                }
            }
            .background(dayBackground(isSelected: isSelected, isToday: isToday, isCurrentMonth: isCurrentMonth))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(dayBorderColor(isSelected: isSelected, isToday: isToday), lineWidth: isSelected || isToday ? 1.2 : 0)
            )
            .opacity(isDisabled ? 0.35 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var analysisBadge: some View {
        ZStack {
            Circle()
                .fill(AppTheme.shared.current.colors.surface)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(AppTheme.shared.current.colors.textPrimary.opacity(0.12), lineWidth: 1)
                )
            Circle()
                .fill(AppTheme.shared.current.colors.accent)
                .frame(width: 5, height: 5)
        }
        .shadow(color: AppTheme.shared.current.colors.accent.opacity(0.22), radius: 3, y: 1)
    }

    private func dot(color: Color, isVisible: Bool) -> some View {
        Circle()
            .fill(isVisible ? color : Color.clear)
            .frame(width: 4, height: 4)
    }

    private func dayBackground(isSelected: Bool, isToday: Bool, isCurrentMonth: Bool) -> Color {
        if isSelected {
            return AppTheme.shared.current.colors.textPrimary
        }
        if isToday {
            return AppTheme.shared.current.colors.accentSoft
        }
        return isCurrentMonth ? AppTheme.shared.current.colors.surfaceHigh.opacity(0.55) : AppTheme.shared.current.colors.surfaceHigh.opacity(0.25)
    }

    private func dayBorderColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return AppTheme.shared.current.colors.textPrimary
        }
        if isToday {
            return AppTheme.shared.current.colors.accent.opacity(0.35)
        }
        return .clear
    }

    private func dayTextColor(isSelected: Bool, isCurrentMonth: Bool, isFutureDay: Bool) -> Color {
        if isSelected {
            return AppTheme.shared.current.colors.bgPrimary
        }
        if !isCurrentMonth || isFutureDay {
            return AppTheme.shared.current.colors.textTertiary
        }
        return AppTheme.shared.current.colors.textPrimary
    }

    private var selectedDaySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Day")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    .kerning(1.1)
                Spacer()
                Text(SkinJourneyFormatters.selectedDay.string(from: selectedDate))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }

            if selectedDate > today {
                Text("Future days can't be logged yet.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let analysisEntry = selectedAnalysisEntry {
                        analysisSummaryCard(entry: analysisEntry)
                    }

                    if let log = selectedLog {
                        checkInSummary(log: log)
                    } else {
                        Text(selectedAnalysisEntry == nil
                             ? "No analysis or check-in saved for this day yet."
                             : "No daily check-in saved for this day yet.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        Button(action: onLogSelectedDay) {
                            Text("Log this day")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.shared.current.colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.45))
        .cornerRadius(20)
    }

    private func analysisSummaryCard(entry: AnalysisCalendarEntry) -> some View {
        let hasLocalPreview = hasLocalPreview(for: entry)
        return HStack(alignment: .top, spacing: 12) {
            analysisPreview(entry: entry)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Skin Analysis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Spacer()
                    Text(SkinJourneyFormatters.scanTime.string(from: entry.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                }

                Text(String(format: "Score %.1f / 10", entry.score))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.shared.current.colors.scoreColor)

                if entry.wasAcceptedQualityOverride {
                    HStack(spacing: 6) {
                        analysisFlag(text: entry.wasLoggedWithMakeup ? "With Makeup" : "Manual Override")
                        if entry.acceptedQualityOverrideReasons.contains(where: { $0 != .heavyMakeup }) {
                            analysisFlag(text: "Lower Confidence")
                        }
                    }
                }

                Text(analysisSummaryText(for: entry, hasLocalPreview: hasLocalPreview))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.surface.opacity(0.88))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func analysisPreview(entry: AnalysisCalendarEntry) -> some View {
        if let previewImage = previewImage(for: entry) {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.shared.current.colors.surface)
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.accent)
            }
            .frame(width: 60, height: 60)
        }
    }

    private func analysisSummaryText(for entry: AnalysisCalendarEntry, hasLocalPreview: Bool) -> String {
        if entry.wasLoggedWithMakeup {
            return "Analyzed anyway with makeup noted in the scan log. Compare trends, not exact score jumps."
        }
        if entry.wasAcceptedQualityOverride {
            return "Analyzed anyway after a quality warning. Treat this scan as lower confidence."
        }
        return !hasLocalPreview
            ? "Analysis saved on this day. Local preview unavailable."
            : "Processed selfie saved locally for your progress history."
    }

    private func analysisFlag(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.shared.current.colors.accentSoft.opacity(0.75))
            .clipShape(Capsule())
    }

    private func previewImage(for entry: AnalysisCalendarEntry) -> UIImage? {
        guard let imageURL = entry.localImageURL else { return nil }
        return UIImage(contentsOfFile: imageURL.path)
    }

    private func hasLocalPreview(for entry: AnalysisCalendarEntry) -> Bool {
        previewImage(for: entry) != nil
    }

    private func checkInSummary(log: SkinJourneyLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Check-In")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                Spacer()
                Button(action: onEditSelectedDay) {
                    Text("Edit")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.shared.current.colors.textPrimary)
                        .clipShape(Capsule())
                }
            }

            if !log.routineStepIDs.isEmpty {
                summaryRow(title: "Routine", ids: log.routineStepIDs)
            }
            if !log.treatmentIDs.isEmpty {
                summaryRow(title: "Treatments", ids: log.treatmentIDs)
            }
            if !log.skinStatusIDs.isEmpty {
                summaryRow(title: "Skin feels", ids: log.skinStatusIDs)
            }
            if !log.note.isEmpty {
                Text(log.note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.shared.current.colors.surface.opacity(0.88))
                    .cornerRadius(14)
            }
        }
    }

    private func summaryRow(title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            FlexibleChipLayout(items: ids) { id in
                Text(SkinJourneyCatalog.title(for: id))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.shared.current.colors.surface)
                    .clipShape(Capsule())
            }
        }
    }

    private func consistencyBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.shared.current.colors.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.shared.current.colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.shared.current.colors.accentSoft.opacity(0.45))
        .cornerRadius(16)
    }

    private var suggestionCard: some View {
        let suggestion = suggestionState.suggestion
        return VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Focus")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                .kerning(1.1)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(suggestion.tint.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: suggestion.symbolName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(suggestion.tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    Text(suggestion.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !suggestion.actionStepIDs.isEmpty {
                FlexibleChipLayout(items: suggestion.actionStepIDs) { id in
                    Text(SkinJourneyCatalog.title(for: id))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(suggestion.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(suggestion.tint.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.45))
        .cornerRadius(20)
    }

    private func shiftMonth(by delta: Int) {
        guard let candidate = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        let nextMonth = min(SkinJourneyCalendar.startOfMonth(for: candidate), currentMonth)
        displayedMonth = nextMonth

        if calendar.isDate(selectedDate, equalTo: nextMonth, toGranularity: .month) {
            return
        }

        let monthLogs = logs
            .filter { calendar.isDate($0.dayStartAt, equalTo: nextMonth, toGranularity: .month) }
            .sorted { $0.dayStartAt > $1.dayStartAt }

        if let latestLoggedDay = monthLogs.first?.dayStartAt {
            selectedDate = latestLoggedDay
        } else {
            selectedDate = nextMonth
        }
    }

    private func handleDayTap(_ day: Date) {
        let normalizedDay = SkinJourneyCalendar.startOfDay(for: day)
        let month = SkinJourneyCalendar.startOfMonth(for: normalizedDay)
        guard month <= currentMonth else { return }
        if !calendar.isDate(normalizedDay, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = month
        }
        selectedDate = normalizedDay
    }

    private func log(for date: Date) -> SkinJourneyLog? {
        logs.first { calendar.isDate($0.dayStartAt, inSameDayAs: date) }
    }

    private func analysisEntry(for date: Date) -> AnalysisCalendarEntry? {
        analysisEntries.first { calendar.isDate($0.dayStartAt, inSameDayAs: date) }
    }
}

struct SkinJourneyLogSheet: View {
    let date: Date
    let existingLog: SkinJourneyLog?
    let onSave: (_ routineStepIDs: [String], _ treatmentIDs: [String], _ skinStatusIDs: [String], _ note: String) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var routineStepIDs: Set<String>
    @State private var treatmentIDs: Set<String>
    @State private var skinStatusIDs: Set<String>
    @State private var note: String

    init(
        date: Date,
        existingLog: SkinJourneyLog?,
        onSave: @escaping (_ routineStepIDs: [String], _ treatmentIDs: [String], _ skinStatusIDs: [String], _ note: String) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.date = date
        self.existingLog = existingLog
        self.onSave = onSave
        self.onDelete = onDelete
        _routineStepIDs = State(initialValue: Set(existingLog?.routineStepIDs ?? []))
        _treatmentIDs = State(initialValue: Set(existingLog?.treatmentIDs ?? []))
        _skinStatusIDs = State(initialValue: Set(existingLog?.skinStatusIDs ?? []))
        _note = State(initialValue: existingLog?.note ?? "")
    }

    private var canSave: Bool {
        !routineStepIDs.isEmpty || !treatmentIDs.isEmpty || !skinStatusIDs.isEmpty || !SkinJourneyLog.trimmedNote(note).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(SkinJourneyFormatters.sheetDay.string(from: date))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.shared.current.colors.textSecondary)

                    selectionSection(title: "Routine", options: SkinJourneyCatalog.routineSteps, selection: $routineStepIDs)
                    selectionSection(title: "Treatments", options: SkinJourneyCatalog.treatments, selection: $treatmentIDs)
                    selectionSection(title: "Skin feels", options: SkinJourneyCatalog.skinStatuses, selection: $skinStatusIDs)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        TextField("Optional note", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .padding(12)
                            .background(AppTheme.shared.current.colors.surfaceHigh.opacity(0.55))
                            .cornerRadius(16)
                            .onChange(of: note) { _, value in
                                note = SkinJourneyLog.trimmedNote(value)
                            }
                        Text("\(note.count)/160")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea())
            .navigationTitle(existingLog == nil ? "Daily Check-In" : "Edit Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            SkinJourneyCatalog.sortedRoutineIDs(Array(routineStepIDs)),
                            SkinJourneyCatalog.sortedTreatmentIDs(Array(treatmentIDs)),
                            SkinJourneyCatalog.sortedSkinStatusIDs(Array(skinStatusIDs)),
                            SkinJourneyLog.trimmedNote(note)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        onSave(
                            SkinJourneyCatalog.sortedRoutineIDs(Array(routineStepIDs)),
                            SkinJourneyCatalog.sortedTreatmentIDs(Array(treatmentIDs)),
                            SkinJourneyCatalog.sortedSkinStatusIDs(Array(skinStatusIDs)),
                            SkinJourneyLog.trimmedNote(note)
                        )
                        dismiss()
                    } label: {
                        Text(existingLog == nil ? "Save Check-In" : "Update Check-In")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.textTertiary)
                            .cornerRadius(18)
                    }
                    .disabled(!canSave)

                    if existingLog != nil, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Log")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppTheme.shared.current.colors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppTheme.shared.current.colors.error.opacity(0.1))
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
    }

    private func selectionSection(title: String, options: [SkinJourneyOption], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)

            FlexibleChipLayout(items: options) { option in
                let isSelected = selection.wrappedValue.contains(option.id)
                Button {
                    if isSelected {
                        selection.wrappedValue.remove(option.id)
                    } else {
                        selection.wrappedValue.insert(option.id)
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? AppTheme.shared.current.colors.bgPrimary : AppTheme.shared.current.colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.surfaceHigh.opacity(0.7))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SkinJourneyOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum SkinJourneyCatalog {
    static let routineSteps: [SkinJourneyOption] = [
        SkinJourneyOption(id: "cleanser", title: "Cleanser"),
        SkinJourneyOption(id: "moisturizer", title: "Moisturizer"),
        SkinJourneyOption(id: "spf", title: "SPF"),
        SkinJourneyOption(id: "night_cleanse", title: "Night Cleanse"),
        SkinJourneyOption(id: "barrier_cream", title: "Barrier Cream"),
        SkinJourneyOption(id: "vitamin_c", title: "Vitamin C"),
        SkinJourneyOption(id: "hydrating_serum", title: "Hydrating Serum"),
        SkinJourneyOption(id: "niacinamide", title: "Niacinamide"),
        SkinJourneyOption(id: "peptide_serum", title: "Peptide Serum"),
        SkinJourneyOption(id: "retinoid", title: "Retinoid"),
        SkinJourneyOption(id: "salicylic_acid", title: "Salicylic Acid"),
        SkinJourneyOption(id: "azelaic_acid", title: "Azelaic Acid"),
        SkinJourneyOption(id: "spot_treatment", title: "Spot Treatment"),
        SkinJourneyOption(id: "overnight_mask", title: "Overnight Mask"),
    ]

    static let treatments: [SkinJourneyOption] = [
        SkinJourneyOption(id: "microneedling", title: "Microneedling"),
        SkinJourneyOption(id: "chemical_peel", title: "Chemical Peel"),
        SkinJourneyOption(id: "led_therapy", title: "LED Therapy"),
        SkinJourneyOption(id: "hydrating_facial", title: "Hydrating Facial"),
        SkinJourneyOption(id: "extraction_facial", title: "Extraction Facial"),
        SkinJourneyOption(id: "dermaplaning", title: "Dermaplaning"),
        SkinJourneyOption(id: "laser", title: "Laser Session"),
    ]

    static let skinStatuses: [SkinJourneyOption] = [
        SkinJourneyOption(id: "dry", title: "Dry / Tight"),
        SkinJourneyOption(id: "sensitive", title: "Sensitive"),
        SkinJourneyOption(id: "redness", title: "Redness"),
        SkinJourneyOption(id: "breakout", title: "Breakout"),
        SkinJourneyOption(id: "irritated", title: "Irritated"),
        SkinJourneyOption(id: "glowy", title: "Glowy"),
    ]

    private static let titleByID: [String: String] = Dictionary(
        uniqueKeysWithValues: (routineSteps + treatments + skinStatuses).map { ($0.id, $0.title) }
    )

    static func title(for id: String) -> String {
        titleByID[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func sortedRoutineIDs(_ ids: [String]) -> [String] {
        sort(ids, using: routineSteps)
    }

    static func sortedTreatmentIDs(_ ids: [String]) -> [String] {
        sort(ids, using: treatments)
    }

    static func sortedSkinStatusIDs(_ ids: [String]) -> [String] {
        sort(ids, using: skinStatuses)
    }

    private static func sort(_ ids: [String], using options: [SkinJourneyOption]) -> [String] {
        let indexByID = Dictionary(uniqueKeysWithValues: options.enumerated().map { ($0.element.id, $0.offset) })
        return Array(Set(ids)).sorted {
            let left = indexByID[$0] ?? Int.max
            let right = indexByID[$1] ?? Int.max
            if left == right {
                return $0 < $1
            }
            return left < right
        }
    }
}

private struct SkinJourneySuggestionState {
    let suggestion: SkinJourneySuggestion
    let bannerMessage: String?
}

private struct SkinJourneySuggestion {
    let title: String
    let message: String
    let actionStepIDs: [String]
    let symbolName: String
    let tint: Color
}

private enum SkinJourneyPlanner {
    private static let recoveryTreatments: Set<String> = ["microneedling", "chemical_peel", "laser"]
    private static let irritationStatuses: Set<String> = ["irritated", "redness", "sensitive"]
    private static let blockedActives: Set<String> = ["retinoid", "salicylic_acid", "chemical_peel"]

    private static let metricSteps: [String: [String]] = [
        "Hydration": ["hydrating_serum", "moisturizer", "spf"],
        "Luminosity": ["vitamin_c", "spf", "hydrating_serum"],
        "Texture": ["retinoid", "niacinamide", "cleanser"],
        "Uniformity": ["vitamin_c", "azelaic_acid", "spf"],
    ]

    static func makeSuggestion(
        latestAnalysis: LocalAnalysis?,
        latestCriteria: [String: Double],
        recentLogs: [SkinJourneyLog],
        last7DayCoverage: Int
    ) -> SkinJourneySuggestionState {
        let today = SkinJourneyCalendar.startOfDay(for: Date())
        let threeDayCutoff = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: today) ?? today
        let recentThreeDayLogs = recentLogs.filter { $0.dayStartAt >= threeDayCutoff }
        let recentTreatment = recentThreeDayLogs.contains { !$0.treatmentIDs.filter(recoveryTreatments.contains).isEmpty }
        let recentIrritation = recentThreeDayLogs.contains { !$0.skinStatusIDs.filter(irritationStatuses.contains).isEmpty }

        let suggestion: SkinJourneySuggestion
        if recentTreatment {
            suggestion = SkinJourneySuggestion(
                title: "Recovery Mode",
                message: "Recent treatment logged. Keep the next few days simple and protect your barrier.",
                actionStepIDs: ["cleanser", "moisturizer", "spf"],
                symbolName: "cross.case",
                tint: AppTheme.shared.current.colors.warning
            )
        } else if recentIrritation {
            suggestion = SkinJourneySuggestion(
                title: "Barrier Reset",
                message: "Your recent logs point to sensitivity. Go gentle and keep your routine focused on comfort.",
                actionStepIDs: ["hydrating_serum", "moisturizer", "spf"],
                symbolName: "shield.lefthalf.filled",
                tint: AppTheme.shared.current.colors.scoreColor
            )
        } else if latestAnalysis != nil, !recentLogs.isEmpty, !latestCriteria.isEmpty {
            let weakestMetric = latestCriteria.min { $0.value < $1.value }?.key ?? "Hydration"
            let baseSteps = metricSteps[weakestMetric] ?? ["cleanser", "moisturizer", "spf"]
            let safeSteps = sanitizedSteps(baseSteps, hasRecentTreatment: recentTreatment, hasRecentIrritation: recentIrritation)
            suggestion = SkinJourneySuggestion(
                title: weakestMetric,
                message: "\(weakestMetric) is your weakest recent area. Build consistency for 7 days and rescan after your next routine streak.",
                actionStepIDs: safeSteps,
                symbolName: "sparkles",
                tint: AppTheme.shared.current.colors.accent
            )
        } else if latestAnalysis != nil {
            suggestion = SkinJourneySuggestion(
                title: "Add Daily Check-Ins",
                message: "You already have a score. Start logging your days so the app can connect your habits to your skin trend.",
                actionStepIDs: ["cleanser", "moisturizer", "spf"],
                symbolName: "calendar.badge.plus",
                tint: AppTheme.shared.current.colors.accent
            )
        } else if !recentLogs.isEmpty {
            suggestion = SkinJourneySuggestion(
                title: "Time For a Scan",
                message: "You are tracking your routine. Add a scan so SkinLit can compare your habits with real score changes.",
                actionStepIDs: [],
                symbolName: "camera.viewfinder",
                tint: AppTheme.shared.current.colors.accent
            )
        } else {
            suggestion = SkinJourneySuggestion(
                title: "Start Your Journey",
                message: "Log your first day here, then scan when you are ready so the app can start spotting patterns over time.",
                actionStepIDs: ["cleanser", "moisturizer", "spf"],
                symbolName: "calendar",
                tint: AppTheme.shared.current.colors.accent
            )
        }

        let bannerMessage: String?
        if last7DayCoverage == 0, latestAnalysis != nil {
            bannerMessage = "Add daily check-ins to make recommendations smarter."
        } else if last7DayCoverage > 0 {
            bannerMessage = "Logged \(last7DayCoverage) of last 7 days."
        } else {
            bannerMessage = nil
        }

        return SkinJourneySuggestionState(suggestion: suggestion, bannerMessage: bannerMessage)
    }

    private static func sanitizedSteps(_ ids: [String], hasRecentTreatment: Bool, hasRecentIrritation: Bool) -> [String] {
        let shouldBlockActives = hasRecentTreatment || hasRecentIrritation
        var result: [String] = []
        var seen = Set<String>()

        for id in ids {
            let safeID: String
            if shouldBlockActives && blockedActives.contains(id) {
                safeID = "hydrating_serum"
            } else {
                safeID = id
            }
            guard seen.insert(safeID).inserted else { continue }
            result.append(safeID)
        }

        return result
    }
}

private enum SkinJourneyCalendar {
    static func startOfDay(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(for: date, calendar: calendar)
    }

    static func visibleDays(for month: Date, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let monthStart = startOfMonth(for: month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = (weekday - calendar.firstWeekday + 7) % 7
        let firstVisibleDay = calendar.date(byAdding: .day, value: -leadingOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstVisibleDay) }
    }
}

private enum SkinJourneyFormatters {
    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let selectedDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static let sheetDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    static let scanTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct FlexibleChipLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func rows() -> [[Data.Element]] {
        var result: [[Data.Element]] = [[]]
        var currentWidth = 0
        let maxCountPerRow = 3

        for item in items {
            if result[result.count - 1].count >= maxCountPerRow || currentWidth >= 3 {
                result.append([item])
                currentWidth = 1
            } else {
                result[result.count - 1].append(item)
                currentWidth += 1
            }
        }

        return result.filter { !$0.isEmpty }
    }
}
