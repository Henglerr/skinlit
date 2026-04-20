import SwiftData
import XCTest
@testable import SkinLit

@MainActor
final class OnboardingDraftRepositoryTests: XCTestCase {
    func testSaveDraftPersistsIncrementalProgressAndNextRoute() throws {
        let repository = try makeRepository()

        try repository.saveDraft(userId: "user-1", gender: "Female", lastCompletedStep: .gender)
        try repository.saveDraft(userId: "user-1", skinTypes: ["Dry", "Sensitive"], lastCompletedStep: .skintype)
        try repository.saveDraft(userId: "user-1", goal: "Glow", lastCompletedStep: .goal)

        let draft = try XCTUnwrap(repository.draft(userId: "user-1"))
        XCTAssertEqual(draft.gender, "Female")
        XCTAssertEqual(Set(repository.skinTypes(for: draft)), Set(["Dry", "Sensitive"]))
        XCTAssertEqual(draft.goal, "Glow")
        XCTAssertEqual(try repository.nextRoute(userId: "user-1"), .onboardingRoutine)
    }

    func testDeleteDraftRemovesSavedProgress() throws {
        let repository = try makeRepository()

        try repository.saveDraft(userId: "user-2", gender: "Male", lastCompletedStep: .gender)
        XCTAssertNotNil(try repository.draft(userId: "user-2"))

        try repository.deleteDraft(userId: "user-2")

        XCTAssertNil(try repository.draft(userId: "user-2"))
        XCTAssertNil(try repository.nextRoute(userId: "user-2"))
    }

    private func makeRepository() throws -> OnboardingDraftRepository {
        let schema = Schema([OnboardingDraft.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return OnboardingDraftRepository(context: ModelContext(container))
    }
}
