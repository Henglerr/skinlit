import Foundation
import SwiftData

public enum OnboardingDraftStep: String, Codable, CaseIterable {
    case gender
    case theme
    case skintype
    case goal
    case routine

    public var nextRoute: AppRoute {
        switch self {
        case .gender:
            return .onboardingTheme
        case .theme:
            return .onboardingSkintype
        case .skintype:
            return .onboardingGoal
        case .goal:
            return .onboardingRoutine
        case .routine:
            return .onboardingRating
        }
    }

    fileprivate var order: Int {
        switch self {
        case .gender:
            return 1
        case .theme:
            return 2
        case .skintype:
            return 3
        case .goal:
            return 4
        case .routine:
            return 5
        }
    }
}

@MainActor
public final class OnboardingDraftRepository {
    private let context: ModelContext
    private let separator = "||"

    public init(context: ModelContext) {
        self.context = context
    }

    public func draft(userId: String) throws -> OnboardingDraft? {
        let predicate = #Predicate<OnboardingDraft> { $0.userId == userId }
        var descriptor = FetchDescriptor<OnboardingDraft>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func saveDraft(
        userId: String,
        gender: String? = nil,
        skinTypes: [String]? = nil,
        goal: String? = nil,
        routine: String? = nil,
        lastCompletedStep: OnboardingDraftStep
    ) throws {
        let existingDraft = try draft(userId: userId)
        let target = existingDraft ?? OnboardingDraft(userId: userId)

        if existingDraft == nil {
            context.insert(target)
        }

        if let gender {
            target.gender = gender
        }

        if let skinTypes {
            target.skinTypesCSV = skinTypes.joined(separator: separator)
        }

        if let goal {
            target.goal = goal
        }

        if let routine {
            target.routine = routine
        }

        target.lastCompletedStepRaw = lastCompletedStep.rawValue
        target.updatedAt = .now
        try context.save()
    }

    public func skinTypes(for draft: OnboardingDraft) -> [String] {
        guard !draft.skinTypesCSV.isEmpty else { return [] }
        return draft.skinTypesCSV
            .components(separatedBy: separator)
            .filter { !$0.isEmpty }
    }

    public func nextRoute(userId: String) throws -> AppRoute? {
        guard
            let existingDraft = try draft(userId: userId),
            let stepRaw = existingDraft.lastCompletedStepRaw,
            let step = OnboardingDraftStep(rawValue: stepRaw)
        else {
            return nil
        }

        return step.nextRoute
    }

    public func deleteDraft(userId: String) throws {
        guard let existing = try draft(userId: userId) else { return }
        context.delete(existing)
        try context.save()
    }

    public func reassignDraft(from oldUserId: String, to newUserId: String) throws {
        guard oldUserId != newUserId else { return }
        guard let source = try draft(userId: oldUserId) else { return }

        if let destination = try draft(userId: newUserId) {
            if let sourceGender = source.gender {
                destination.gender = sourceGender
            }

            if !source.skinTypesCSV.isEmpty {
                destination.skinTypesCSV = source.skinTypesCSV
            }

            if let sourceGoal = source.goal {
                destination.goal = sourceGoal
            }

            if let sourceRoutine = source.routine {
                destination.routine = sourceRoutine
            }

            let preferredStep = preferredStep(
                sourceRaw: source.lastCompletedStepRaw,
                destinationRaw: destination.lastCompletedStepRaw
            )
            destination.lastCompletedStepRaw = preferredStep?.rawValue
            destination.updatedAt = max(source.updatedAt, destination.updatedAt)
            context.delete(source)
        } else {
            source.id = newUserId
            source.userId = newUserId
        }

        try context.save()
    }

    private func preferredStep(sourceRaw: String?, destinationRaw: String?) -> OnboardingDraftStep? {
        let sourceStep = sourceRaw.flatMap(OnboardingDraftStep.init(rawValue:))
        let destinationStep = destinationRaw.flatMap(OnboardingDraftStep.init(rawValue:))

        switch (sourceStep, destinationStep) {
        case (.some(let source), .some(let destination)):
            return source.order >= destination.order ? source : destination
        case (.some(let source), .none):
            return source
        case (.none, .some(let destination)):
            return destination
        case (.none, .none):
            return nil
        }
    }
}
