import Foundation
import SwiftData

@Model
public final class OnboardingDraft {
    @Attribute(.unique) public var id: String
    public var userId: String
    public var gender: String?
    public var skinTypesCSV: String
    public var goal: String?
    public var routine: String?
    public var lastCompletedStepRaw: String?
    public var updatedAt: Date

    public init(
        userId: String,
        gender: String? = nil,
        skinTypesCSV: String = "",
        goal: String? = nil,
        routine: String? = nil,
        lastCompletedStepRaw: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = userId
        self.userId = userId
        self.gender = gender
        self.skinTypesCSV = skinTypesCSV
        self.goal = goal
        self.routine = routine
        self.lastCompletedStepRaw = lastCompletedStepRaw
        self.updatedAt = updatedAt
    }
}
