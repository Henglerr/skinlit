import Foundation
import SwiftData

@Model
public final class SkinJourneyLog {
    @Attribute(.unique) public var id: String
    public var userId: String
    public var dayKey: String
    public var dayStartAt: Date
    public var routineStepIDsCSV: String
    public var treatmentIDsCSV: String
    public var skinStatusIDsCSV: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        userId: String,
        dayKey: String,
        dayStartAt: Date,
        routineStepIDsCSV: String,
        treatmentIDsCSV: String,
        skinStatusIDsCSV: String,
        note: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.dayKey = dayKey
        self.dayStartAt = dayStartAt
        self.routineStepIDsCSV = routineStepIDsCSV
        self.treatmentIDsCSV = treatmentIDsCSV
        self.skinStatusIDsCSV = skinStatusIDsCSV
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SkinJourneyLog {
    public static let csvSeparator = "||"

    public var routineStepIDs: [String] {
        Self.decodeCSV(routineStepIDsCSV)
    }

    public var treatmentIDs: [String] {
        Self.decodeCSV(treatmentIDsCSV)
    }

    public var skinStatusIDs: [String] {
        Self.decodeCSV(skinStatusIDsCSV)
    }

    public static func encodeCSV(_ ids: [String]) -> String {
        uniqueNonEmpty(ids).joined(separator: csvSeparator)
    }

    public static func decodeCSV(_ csv: String) -> [String] {
        guard !csv.isEmpty else { return [] }
        return uniqueNonEmpty(csv.components(separatedBy: csvSeparator))
    }

    public static func trimmedNote(_ note: String, limit: Int = 160) -> String {
        let singleLine = note
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func mergedNote(primary: String, secondary: String, limit: Int = 160) -> String {
        let parts = [trimmedNote(primary, limit: limit), trimmedNote(secondary, limit: limit)]
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        return trimmedNote(parts.joined(separator: " | "), limit: limit)
    }

    private static func uniqueNonEmpty(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }
}
