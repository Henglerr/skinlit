import Foundation
import SwiftData

@MainActor
public final class SkinJourneyRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func log(userId: String, on date: Date) throws -> SkinJourneyLog? {
        let key = Self.dayKey(for: date)
        let predicate = #Predicate<SkinJourneyLog> {
            $0.userId == userId && $0.dayKey == key
        }
        var descriptor = FetchDescriptor<SkinJourneyLog>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchLogs(userId: String) throws -> [SkinJourneyLog] {
        let predicate = #Predicate<SkinJourneyLog> { $0.userId == userId }
        let descriptor = FetchDescriptor<SkinJourneyLog>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dayStartAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func upsertLog(
        userId: String,
        date: Date,
        routineStepIDs: [String],
        treatmentIDs: [String],
        skinStatusIDs: [String],
        note: String
    ) throws {
        let normalizedNote = SkinJourneyLog.trimmedNote(note)
        let encodedRoutine = SkinJourneyLog.encodeCSV(routineStepIDs)
        let encodedTreatments = SkinJourneyLog.encodeCSV(treatmentIDs)
        let encodedStatuses = SkinJourneyLog.encodeCSV(skinStatusIDs)

        if encodedRoutine.isEmpty,
           encodedTreatments.isEmpty,
           encodedStatuses.isEmpty,
           normalizedNote.isEmpty {
            try deleteLog(userId: userId, date: date)
            return
        }

        let normalizedDay = Self.startOfDay(for: date)
        let key = Self.dayKey(for: normalizedDay)

        if let existing = try log(userId: userId, on: normalizedDay) {
            existing.routineStepIDsCSV = encodedRoutine
            existing.treatmentIDsCSV = encodedTreatments
            existing.skinStatusIDsCSV = encodedStatuses
            existing.note = normalizedNote
            existing.updatedAt = .now
        } else {
            let item = SkinJourneyLog(
                id: Self.logID(for: userId, dayKey: key),
                userId: userId,
                dayKey: key,
                dayStartAt: normalizedDay,
                routineStepIDsCSV: encodedRoutine,
                treatmentIDsCSV: encodedTreatments,
                skinStatusIDsCSV: encodedStatuses,
                note: normalizedNote
            )
            context.insert(item)
        }

        try context.save()
    }

    public func deleteLog(userId: String, date: Date) throws {
        guard let existing = try log(userId: userId, on: date) else { return }
        context.delete(existing)
        try context.save()
    }

    public func reassignLogs(from oldUserId: String, to newUserId: String) throws {
        guard oldUserId != newUserId else { return }

        let predicate = #Predicate<SkinJourneyLog> { $0.userId == oldUserId }
        let descriptor = FetchDescriptor<SkinJourneyLog>(predicate: predicate)
        let logs = try context.fetch(descriptor)

        for item in logs {
            if let destination = try log(userId: newUserId, on: item.dayStartAt) {
                destination.routineStepIDsCSV = SkinJourneyLog.encodeCSV(destination.routineStepIDs + item.routineStepIDs)
                destination.treatmentIDsCSV = SkinJourneyLog.encodeCSV(destination.treatmentIDs + item.treatmentIDs)
                destination.skinStatusIDsCSV = SkinJourneyLog.encodeCSV(destination.skinStatusIDs + item.skinStatusIDs)
                destination.note = SkinJourneyLog.mergedNote(primary: destination.note, secondary: item.note)
                destination.updatedAt = max(destination.updatedAt, item.updatedAt)
                context.delete(item)
            } else {
                item.userId = newUserId
                item.id = Self.logID(for: newUserId, dayKey: item.dayKey)
                item.updatedAt = .now
            }
        }

        try context.save()
    }

    public func deleteLogs(userId: String) throws {
        let predicate = #Predicate<SkinJourneyLog> { $0.userId == userId }
        let descriptor = FetchDescriptor<SkinJourneyLog>(predicate: predicate)
        let logs = try context.fetch(descriptor)
        for item in logs {
            context.delete(item)
        }
        try context.save()
    }

    public static func startOfDay(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func dayKey(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startOfDay(for: date))
    }

    public static func logID(for userId: String, dayKey: String) -> String {
        "\(userId)_\(dayKey)"
    }
}
