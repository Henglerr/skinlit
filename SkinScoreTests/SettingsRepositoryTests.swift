import SwiftData
import XCTest
@testable import SkinScore

@MainActor
final class SettingsRepositoryTests: XCTestCase {
    func testNotificationPromptStateRoundTrips() throws {
        let repository = try makeRepository()

        try repository.setNotificationPromptState(.softDeclined, promptedAt: .now)

        XCTAssertEqual(try repository.notificationPromptState(), .softDeclined)
    }

    func testLastActiveAtRoundTrips() throws {
        let repository = try makeRepository()
        let expectedDate = Date(timeIntervalSince1970: 1_736_000_000)

        try repository.setLastActiveAt(expectedDate)

        XCTAssertEqual(try repository.lastActiveAt(), expectedDate)
    }

    private func makeRepository() throws -> SettingsRepository {
        let schema = Schema([AppLocalSettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SettingsRepository(context: ModelContext(container))
    }
}
