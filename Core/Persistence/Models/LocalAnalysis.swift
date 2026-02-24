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
    public var criteriaJSON: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        score: Double,
        summary: String,
        skinTypeDetected: String,
        imageHash: String? = nil,
        criteriaJSON: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.score = score
        self.summary = summary
        self.skinTypeDetected = skinTypeDetected
        self.imageHash = imageHash
        self.criteriaJSON = criteriaJSON
        self.createdAt = createdAt
    }
}
