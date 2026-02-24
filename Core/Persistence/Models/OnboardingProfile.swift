import Foundation
import SwiftData

@Model
public final class OnboardingProfile {
    @Attribute(.unique) public var id: String
    public var userId: String
    public var skinTypesCSV: String
    public var goal: String
    public var routine: String
    public var completedAt: Date

    public init(
        userId: String,
        skinTypesCSV: String,
        goal: String,
        routine: String,
        completedAt: Date = .now
    ) {
        self.id = userId
        self.userId = userId
        self.skinTypesCSV = skinTypesCSV
        self.goal = goal
        self.routine = routine
        self.completedAt = completedAt
    }
}
