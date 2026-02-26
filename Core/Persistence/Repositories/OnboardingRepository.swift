import Foundation
import SwiftData

@MainActor
public final class OnboardingRepository {
    private let context: ModelContext
    private let separator = "||"

    public init(context: ModelContext) {
        self.context = context
    }

    public func profile(userId: String) throws -> OnboardingProfile? {
        let predicate = #Predicate<OnboardingProfile> { $0.userId == userId }
        var descriptor = FetchDescriptor<OnboardingProfile>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func hasCompletedOnboarding(userId: String) throws -> Bool {
        try profile(userId: userId) != nil
    }

    public func saveOnboarding(
        userId: String,
        skinTypes: [String],
        goal: String,
        routine: String
    ) throws {
        let encodedSkinTypes = skinTypes.joined(separator: separator)
        if let existing = try profile(userId: userId) {
            existing.skinTypesCSV = encodedSkinTypes
            existing.goal = goal
            existing.routine = routine
            existing.completedAt = .now
        } else {
            let newProfile = OnboardingProfile(
                userId: userId,
                skinTypesCSV: encodedSkinTypes,
                goal: goal,
                routine: routine
            )
            context.insert(newProfile)
        }
        try context.save()
    }

    public func reassignProfile(from oldUserId: String, to newUserId: String) throws {
        guard oldUserId != newUserId else { return }
        guard let oldProfile = try profile(userId: oldUserId) else { return }

        if let destination = try profile(userId: newUserId) {
            destination.skinTypesCSV = oldProfile.skinTypesCSV
            destination.goal = oldProfile.goal
            destination.routine = oldProfile.routine
            destination.completedAt = oldProfile.completedAt
            context.delete(oldProfile)
        } else {
            oldProfile.userId = newUserId
            oldProfile.id = newUserId
        }

        try context.save()
    }

    /// Deletes the onboarding record for a user, forcing them back through onboarding.
    /// Only called in DEBUG builds when RESET_ONBOARDING_EACH_LAUNCH = true.
    public func resetOnboarding(userId: String) throws {
        guard let existing = try profile(userId: userId) else { return }
        context.delete(existing)
        try context.save()
    }

    public func deleteProfile(userId: String) throws {
        guard let existing = try profile(userId: userId) else { return }
        context.delete(existing)
        try context.save()
    }
}
