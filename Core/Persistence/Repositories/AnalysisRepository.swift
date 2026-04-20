import Foundation
import SwiftData

@MainActor
public final class AnalysisRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func analysis(byId id: String) throws -> LocalAnalysis? {
        let predicate = #Predicate<LocalAnalysis> { $0.id == id }
        var descriptor = FetchDescriptor<LocalAnalysis>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func analysis(byImageHash imageHash: String, userId: String) throws -> LocalAnalysis? {
        let imageHashValue: String? = imageHash
        let predicate = #Predicate<LocalAnalysis> {
            $0.userId == userId && $0.imageHash == imageHashValue
        }
        var descriptor = FetchDescriptor<LocalAnalysis>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func updateAnalysisLocalImagePath(id: String, localImageRelativePath: String?) throws {
        guard let existing = try analysis(byId: id) else { return }
        existing.localImageRelativePath = localImageRelativePath
        try context.save()
    }

    public func updateAnalysisDebugMetadata(id: String, debugMetadataJSON: String? = nil) throws {
        guard let existing = try analysis(byId: id) else { return }
        if let debugMetadataJSON {
            existing.debugMetadataJSON = debugMetadataJSON
        }
        try context.save()
    }

    public func saveAnalysis(
        id: String,
        userId: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String?,
        localImageRelativePath: String? = nil,
        criteriaJSON: String,
        criterionInsightsJSON: String? = nil,
        debugMetadataJSON: String?,
        createdAt: Date? = nil
    ) throws {
        if let existing = try analysis(byId: id) {
            existing.userId = userId
            existing.score = score
            existing.summary = summary
            existing.skinTypeDetected = skinTypeDetected
            if let imageHash {
                existing.imageHash = imageHash
            }
            if let localImageRelativePath {
                existing.localImageRelativePath = localImageRelativePath
            }
            existing.criteriaJSON = criteriaJSON
            if let criterionInsightsJSON {
                existing.criterionInsightsJSON = criterionInsightsJSON
            }
            if let debugMetadataJSON {
                existing.debugMetadataJSON = debugMetadataJSON
            }
            if let createdAt {
                existing.createdAt = createdAt
            }
        } else {
            let analysis = LocalAnalysis(
                id: id,
                userId: userId,
                score: score,
                summary: summary,
                skinTypeDetected: skinTypeDetected,
                imageHash: imageHash,
                localImageRelativePath: localImageRelativePath,
                criteriaJSON: criteriaJSON,
                criterionInsightsJSON: criterionInsightsJSON,
                debugMetadataJSON: debugMetadataJSON,
                createdAt: createdAt ?? .now
            )
            context.insert(analysis)
        }
        try context.save()
    }

    public func fetchAllAnalyses(userId: String) throws -> [LocalAnalysis] {
        let predicate = #Predicate<LocalAnalysis> { $0.userId == userId }
        let descriptor = FetchDescriptor<LocalAnalysis>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func fetchRecentAnalyses(userId: String, limit: Int = 20) throws -> [LocalAnalysis] {
        let predicate = #Predicate<LocalAnalysis> { $0.userId == userId }
        var descriptor = FetchDescriptor<LocalAnalysis>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func totalAnalysisCount() throws -> Int {
        let descriptor = FetchDescriptor<LocalAnalysis>()
        return try context.fetchCount(descriptor)
    }

    public func analysisCount(userId: String) throws -> Int {
        let predicate = #Predicate<LocalAnalysis> { $0.userId == userId }
        let descriptor = FetchDescriptor<LocalAnalysis>(predicate: predicate)
        return try context.fetchCount(descriptor)
    }

    public func currentScanDayStreak(userId: String, calendar: Calendar = .autoupdatingCurrent) throws -> Int {
        let predicate = #Predicate<LocalAnalysis> { $0.userId == userId }
        let descriptor = FetchDescriptor<LocalAnalysis>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let analyses = try context.fetch(descriptor)
        return Self.consecutiveScanDayStreak(
            forDescendingScanDates: analyses.map(\.createdAt),
            calendar: calendar
        )
    }

    static func consecutiveScanDayStreak(
        forDescendingScanDates scanDates: [Date],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        var streak = 0
        var previousUniqueDay: Date?

        for scanDate in scanDates {
            let day = calendar.startOfDay(for: scanDate)

            if day == previousUniqueDay {
                continue
            }

            if let previousUniqueDay {
                guard
                    let expectedPreviousDay = calendar.date(byAdding: .day, value: -1, to: previousUniqueDay),
                    day == expectedPreviousDay
                else {
                    break
                }
            }

            streak += 1
            previousUniqueDay = day
        }

        return streak
    }

    public func reassignAnalyses(from oldUserId: String, to newUserId: String) throws {
        guard oldUserId != newUserId else { return }
        let predicate = #Predicate<LocalAnalysis> { $0.userId == oldUserId }
        let descriptor = FetchDescriptor<LocalAnalysis>(predicate: predicate)
        let analyses = try context.fetch(descriptor)
        for analysis in analyses {
            analysis.userId = newUserId
        }
        try context.save()
    }

    public func deleteAnalyses(userId: String) throws {
        let predicate = #Predicate<LocalAnalysis> { $0.userId == userId }
        let descriptor = FetchDescriptor<LocalAnalysis>(predicate: predicate)
        let analyses = try context.fetch(descriptor)
        for analysis in analyses {
            context.delete(analysis)
        }
        try context.save()
    }
}
