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

    public func touchAnalysis(id: String) throws {
        guard let existing = try analysis(byId: id) else { return }
        existing.createdAt = .now
        try context.save()
    }

    public func saveAnalysis(
        id: String,
        userId: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String?,
        criteriaJSON: String
    ) throws {
        if let existing = try analysis(byId: id) {
            existing.userId = userId
            existing.score = score
            existing.summary = summary
            existing.skinTypeDetected = skinTypeDetected
            existing.imageHash = imageHash
            existing.criteriaJSON = criteriaJSON
            existing.createdAt = .now
        } else {
            let analysis = LocalAnalysis(
                id: id,
                userId: userId,
                score: score,
                summary: summary,
                skinTypeDetected: skinTypeDetected,
                imageHash: imageHash,
                criteriaJSON: criteriaJSON
            )
            context.insert(analysis)
        }
        try context.save()
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
