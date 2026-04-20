import Foundation
import SwiftData

@Model
public final class LocalAnalysis {
    @Attribute(.unique) public var id: String
    public var userId: String
    public var score: Double
    public var summary: String
    public var skinTypeDetected: String
    public var imageHash: String?
    public var localImageRelativePath: String?
    public var criteriaJSON: String
    public var criterionInsightsJSON: String?
    public var debugMetadataJSON: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String? = nil,
        localImageRelativePath: String? = nil,
        criteriaJSON: String,
        criterionInsightsJSON: String? = nil,
        debugMetadataJSON: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.score = score
        self.summary = summary
        self.skinTypeDetected = skinTypeDetected
        self.imageHash = imageHash
        self.localImageRelativePath = localImageRelativePath
        self.criteriaJSON = criteriaJSON
        self.criterionInsightsJSON = criterionInsightsJSON
        self.debugMetadataJSON = debugMetadataJSON
        self.createdAt = createdAt
    }
}

public struct AnalysisCalendarEntry: Identifiable, Equatable {
    public let analysisID: String
    public let dayStartAt: Date
    public let createdAt: Date
    public let score: Double
    public let localImageRelativePath: String?
    public let debugMetadata: LocalAnalysisDebugMetadata?

    public var id: String { analysisID }

    public var localImageURL: URL? {
        FileSystemAnalysisPhotoStore.fileURL(forRelativePath: localImageRelativePath)
    }

    public var acceptedQualityOverrideReasons: [SkinImageQualityReason] {
        debugMetadata?.qualityOverrideAcceptedReasons ?? []
    }

    public var wasAcceptedQualityOverride: Bool {
        debugMetadata?.qualityOverrideAccepted == true
    }

    public var wasLoggedWithMakeup: Bool {
        acceptedQualityOverrideReasons.contains(.heavyMakeup)
    }
}

public extension LocalAnalysis {
    var criterionInsights: [String: SkinCriterionInsight]? {
        guard
            let criterionInsightsJSON,
            let data = criterionInsightsJSON.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([String: SkinCriterionInsight].self, from: data)
    }

    var debugMetadata: LocalAnalysisDebugMetadata? {
        guard
            let debugMetadataJSON,
            let data = debugMetadataJSON.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(LocalAnalysisDebugMetadata.self, from: data)
    }
}
