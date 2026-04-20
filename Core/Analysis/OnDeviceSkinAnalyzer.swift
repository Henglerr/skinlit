import Foundation

public struct SkinCriterionInsight: Equatable, Codable {
    public let status: String
    public let summary: String
    public let positiveObservations: [String]
    public let negativeObservations: [String]
    public let routineFocus: String

    public init(
        status: String,
        summary: String,
        positiveObservations: [String],
        negativeObservations: [String],
        routineFocus: String
    ) {
        self.status = status
        self.summary = summary
        self.positiveObservations = positiveObservations
        self.negativeObservations = negativeObservations
        self.routineFocus = routineFocus
    }

    enum CodingKeys: String, CodingKey {
        case status
        case summary
        case positiveObservations = "positive_observations"
        case negativeObservations = "negative_observations"
        case routineFocus = "routine_focus"
    }
}

// Shared result model kept for remote analysis responses. Local image processing
// no longer exists in the app runtime.
public struct OnDeviceAnalysisResult: Equatable, Codable {
    public let score: Double
    public let summary: String
    public let skinTypeDetected: String
    public let criteria: [String: Double]
    public let criterionInsights: [String: SkinCriterionInsight]?

    public init(
        score: Double,
        summary: String,
        skinTypeDetected: String,
        criteria: [String: Double],
        criterionInsights: [String: SkinCriterionInsight]? = nil
    ) {
        self.score = score
        self.summary = summary
        self.skinTypeDetected = skinTypeDetected
        self.criteria = criteria
        self.criterionInsights = criterionInsights
    }
}
