import Foundation

public struct FreeAnalysisDTO: Codable {
    public let score: Double
    public let summary: String
    public let skinTypeDetected: String
    
    enum CodingKeys: String, CodingKey {
        case score
        case summary
        case skinTypeDetected = "skin_type_detected"
    }
}

public struct PremiumAnalysisDTO: Codable {
    public let criteria: [String: Double]
    public let suggestions: [String]
    public let strengths: [String]
    
    enum CodingKeys: String, CodingKey {
        case criteria
        case suggestions
        case strengths = "skin_strengths"
    }
}

public enum ResultAccessState {
    case freeLocked
    case premiumUnlocked
}
