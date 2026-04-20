import AuthenticationServices
import UIKit
import SwiftData
import XCTest
@testable import SkinLit

@MainActor
final class AnalysisRepositoryTests: XCTestCase {
    func testCurrentScanDayStreakReturnsZeroWhenNoAnalyses() throws {
        let repository = try makeRepository()

        XCTAssertEqual(
            try repository.currentScanDayStreak(userId: "user-1", calendar: makeUTCCalendar()),
            0
        )
    }

    func testCurrentScanDayStreakTreatsMultipleScansOnSameDayAsOneDay() throws {
        let repository = try makeRepository()
        let calendar = makeUTCCalendar()
        let day = makeDate(year: 2026, month: 3, day: 6, hour: 12, calendar: calendar)

        try saveAnalysis(repository, id: "scan-1", score: 4.1, createdAt: day)
        try saveAnalysis(
            repository,
            id: "scan-2",
            score: 4.6,
            createdAt: calendar.date(byAdding: .hour, value: -3, to: day)
        )

        XCTAssertEqual(
            try repository.currentScanDayStreak(userId: "user-1", calendar: calendar),
            1
        )
    }

    func testCurrentScanDayStreakStopsAtFirstMissingDay() throws {
        let repository = try makeRepository()
        let calendar = makeUTCCalendar()
        let latestDay = makeDate(year: 2026, month: 3, day: 6, hour: 12, calendar: calendar)

        try saveAnalysis(repository, id: "scan-1", score: 7.2, createdAt: latestDay)
        try saveAnalysis(
            repository,
            id: "scan-2",
            score: 7.0,
            createdAt: calendar.date(byAdding: .day, value: -1, to: latestDay)
        )
        try saveAnalysis(
            repository,
            id: "scan-3",
            score: 6.8,
            createdAt: calendar.date(byAdding: .day, value: -3, to: latestDay)
        )

        XCTAssertEqual(
            try repository.currentScanDayStreak(userId: "user-1", calendar: calendar),
            2
        )
    }

    func testCurrentScanDayStreakReturnsActualLengthBeyondSevenDays() throws {
        let repository = try makeRepository()
        let calendar = makeUTCCalendar()
        let latestDay = makeDate(year: 2026, month: 3, day: 6, hour: 12, calendar: calendar)

        for offset in 0..<9 {
            try saveAnalysis(
                repository,
                id: "scan-\(offset)",
                score: 5.0 + Double(offset) * 0.1,
                createdAt: calendar.date(byAdding: .day, value: -offset, to: latestDay)
            )
        }

        XCTAssertEqual(
            try repository.currentScanDayStreak(userId: "user-1", calendar: calendar),
            9
        )
    }

    func testSaveAnalysisUsesExplicitCreatedAtOnInsert() throws {
        let repository = try makeRepository()
        let expectedCreatedAt = Date(timeIntervalSince1970: 1_736_000_000)

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 5.4,
            createdAt: expectedCreatedAt
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.createdAt, expectedCreatedAt)
    }

    func testSaveAnalysisPersistsLocalImageRelativePathOnInsert() throws {
        let repository = try makeRepository()

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 5.4,
            summary: "summary",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            localImageRelativePath: "AnalysisPhotos/scan-1.jpg",
            criteriaJSON: "{\"Hydration\":7}",
            debugMetadataJSON: nil,
            createdAt: Date(timeIntervalSince1970: 1_736_000_000)
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.localImageRelativePath, "AnalysisPhotos/scan-1.jpg")
    }

    func testSaveAnalysisPersistsCriterionInsightsJSONOnInsert() throws {
        let repository = try makeRepository()
        let criterionInsightsJSON = try makeCriterionInsightsJSON()

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 5.4,
            summary: "summary",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            criteriaJSON: "{\"Hydration\":7}",
            criterionInsightsJSON: criterionInsightsJSON,
            debugMetadataJSON: nil,
            createdAt: Date(timeIntervalSince1970: 1_736_000_000)
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        let hydration = try XCTUnwrap(saved.criterionInsights?["Hydration"])
        XCTAssertEqual(hydration.status, "Balanced")
        XCTAssertEqual(hydration.summary, "Hydration looks mostly comfortable with light dryness around the cheeks.")
        XCTAssertEqual(hydration.positiveObservations, ["The central face does not show obvious flaking."])
        XCTAssertEqual(hydration.negativeObservations, ["The cheek area may be pulling the hydration score down slightly."])
        XCTAssertEqual(hydration.routineFocus, "Keep a barrier-supporting moisturizer consistent at night.")
    }

    func testSaveAnalysisPreservesCriterionInsightsWhenUpdatingWithoutNewPayload() throws {
        let repository = try makeRepository()
        let criterionInsightsJSON = try makeCriterionInsightsJSON()

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 5.4,
            summary: "summary",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            criteriaJSON: "{\"Hydration\":7}",
            criterionInsightsJSON: criterionInsightsJSON,
            debugMetadataJSON: nil,
            createdAt: Date(timeIntervalSince1970: 1_736_000_000)
        )

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 6.0,
            summary: "remote update without insights",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            criteriaJSON: "{\"Hydration\":8}",
            debugMetadataJSON: nil
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertNotNil(saved.criterionInsights?["Hydration"])
        XCTAssertEqual(saved.criterionInsights?["Hydration"]?.status, "Balanced")
    }

    func testSaveAnalysisPreservesCreatedAtWhenUpdatingWithoutExplicitTimestamp() throws {
        let repository = try makeRepository()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_736_000_000)

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 4.2,
            createdAt: originalCreatedAt
        )

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 7.1
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.score, 7.1)
        XCTAssertEqual(saved.createdAt, originalCreatedAt)
    }

    func testSaveAnalysisPreservesLocalImageRelativePathWhenUpdatingWithoutNewPath() throws {
        let repository = try makeRepository()

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 4.2,
            summary: "summary",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            localImageRelativePath: "AnalysisPhotos/scan-1.jpg",
            criteriaJSON: "{\"Hydration\":7}",
            debugMetadataJSON: nil,
            createdAt: Date(timeIntervalSince1970: 1_736_000_000)
        )

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 7.1,
            summary: "updated",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            criteriaJSON: "{\"Hydration\":8}",
            debugMetadataJSON: nil
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.localImageRelativePath, "AnalysisPhotos/scan-1.jpg")
    }

    func testSaveAnalysisRepairsCreatedAtWhenExplicitRemoteTimestampProvided() throws {
        let repository = try makeRepository()
        let wrongCreatedAt = Date(timeIntervalSince1970: 1_736_000_300)
        let canonicalCreatedAt = Date(timeIntervalSince1970: 1_736_000_100)

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 4.2,
            createdAt: wrongCreatedAt
        )

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 4.2,
            createdAt: canonicalCreatedAt
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.createdAt, canonicalCreatedAt)
    }

    func testUpdateAnalysisDebugMetadataDoesNotChangeCreatedAt() throws {
        let repository = try makeRepository()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_736_000_000)

        try saveAnalysis(
            repository,
            id: "scan-1",
            score: 4.2,
            createdAt: originalCreatedAt
        )

        try repository.updateAnalysisDebugMetadata(
            id: "scan-1",
            debugMetadataJSON: "{\"source\":\"local_cache\"}"
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.createdAt, originalCreatedAt)
        XCTAssertEqual(saved.debugMetadataJSON, "{\"source\":\"local_cache\"}")
    }

    func testFetchRecentAnalysesUsesCanonicalCreatedAtNotSyncLoopOrder() throws {
        let repository = try makeRepository()
        let oldest = Date(timeIntervalSince1970: 1_736_000_000)
        let middle = Date(timeIntervalSince1970: 1_736_000_100)
        let newest = Date(timeIntervalSince1970: 1_736_000_200)

        // Simulate remote sync providing scans newest-first.
        try saveAnalysis(repository, id: "scan-newest", score: 8.5, createdAt: newest)
        try saveAnalysis(repository, id: "scan-middle", score: 6.0, createdAt: middle)
        try saveAnalysis(repository, id: "scan-oldest", score: 3.5, createdAt: oldest)

        let recent = try repository.fetchRecentAnalyses(userId: "user-1", limit: 10)

        XCTAssertEqual(recent.map(\.id), ["scan-newest", "scan-middle", "scan-oldest"])
        XCTAssertEqual(
            recent.sorted { $0.createdAt < $1.createdAt }.map(\.id),
            ["scan-oldest", "scan-middle", "scan-newest"]
        )
    }

    func testCacheHitMetadataUpdateDoesNotReorderRecentAnalyses() throws {
        let repository = try makeRepository()
        let older = Date(timeIntervalSince1970: 1_736_000_000)
        let newer = Date(timeIntervalSince1970: 1_736_000_100)

        try saveAnalysis(repository, id: "scan-old", score: 4.2, createdAt: older)
        try saveAnalysis(repository, id: "scan-new", score: 7.1, createdAt: newer)

        try repository.updateAnalysisDebugMetadata(
            id: "scan-old",
            debugMetadataJSON: "{\"source\":\"local_cache\"}"
        )

        let recent = try repository.fetchRecentAnalyses(userId: "user-1", limit: 10)
        XCTAssertEqual(recent.map(\.id), ["scan-new", "scan-old"])
    }

    func testRemoteStyleUpdateDoesNotOverwriteExistingLocalImageRelativePath() throws {
        let repository = try makeRepository()
        let createdAt = Date(timeIntervalSince1970: 1_736_000_000)

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 6.1,
            summary: "summary",
            skinTypeDetected: "Combination",
            imageHash: "hash-1",
            localImageRelativePath: "AnalysisPhotos/scan-1.jpg",
            criteriaJSON: "{\"Hydration\":7}",
            debugMetadataJSON: nil,
            createdAt: createdAt
        )

        try repository.saveAnalysis(
            id: "scan-1",
            userId: "user-1",
            score: 6.3,
            summary: "remote update",
            skinTypeDetected: "Combination",
            imageHash: nil,
            criteriaJSON: "{\"Hydration\":8}",
            debugMetadataJSON: "{\"source\":\"remote_sync\"}",
            createdAt: createdAt
        )

        let saved = try XCTUnwrap(repository.analysis(byId: "scan-1"))
        XCTAssertEqual(saved.localImageRelativePath, "AnalysisPhotos/scan-1.jpg")
    }

    func testRefreshRecentAnalysesLoadsPersistenceBackedStreakAndCount() throws {
        let harness = try makeAppStateHarness()
        let calendar = makeUTCCalendar()
        let latestDay = makeDate(year: 2026, month: 3, day: 6, hour: 18, calendar: calendar)

        for dayOffset in 0..<5 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -dayOffset, to: latestDay))
            for hourOffset in 0..<4 {
                try saveAnalysis(
                    harness.analysisRepository,
                    id: "dense-\(dayOffset)-\(hourOffset)",
                    score: 6.0 + Double(dayOffset) * 0.1,
                    createdAt: calendar.date(byAdding: .hour, value: -(hourOffset * 2), to: day)
                )
            }
        }

        for dayOffset in 5..<7 {
            try saveAnalysis(
                harness.analysisRepository,
                id: "streak-\(dayOffset)",
                score: 6.5,
                createdAt: calendar.date(byAdding: .day, value: -dayOffset, to: latestDay)
            )
        }

        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .guest,
            providerUserId: nil,
            email: nil,
            displayName: nil
        )

        harness.appState.refreshRecentAnalyses()

        XCTAssertEqual(harness.appState.totalScanCount, 22)
        XCTAssertEqual(harness.appState.scanDayStreakCount, 7)
        XCTAssertEqual(harness.appState.recentAnalyses.count, 20)
        XCTAssertEqual(
            Set(harness.appState.recentAnalyses.map { calendar.startOfDay(for: $0.createdAt) }).count,
            5
        )
    }

    func testRefreshRecentAnalysesBuildsCalendarEntriesUsingLatestAnalysisPerDay() throws {
        let harness = try makeAppStateHarness()
        let calendar = makeUTCCalendar()
        let firstScan = makeDate(year: 2026, month: 3, day: 6, hour: 9, calendar: calendar)
        let latestScanSameDay = makeDate(year: 2026, month: 3, day: 6, hour: 18, calendar: calendar)
        let secondDay = makeDate(year: 2026, month: 3, day: 5, hour: 12, calendar: calendar)

        try harness.analysisRepository.saveAnalysis(
            id: "scan-older",
            userId: "user-1",
            score: 4.8,
            summary: "older",
            skinTypeDetected: "Combination",
            imageHash: "hash-older",
            localImageRelativePath: "AnalysisPhotos/scan-older.jpg",
            criteriaJSON: "{\"Hydration\":6}",
            debugMetadataJSON: nil,
            createdAt: firstScan
        )
        try harness.analysisRepository.saveAnalysis(
            id: "scan-latest",
            userId: "user-1",
            score: 7.3,
            summary: "latest",
            skinTypeDetected: "Combination",
            imageHash: "hash-latest",
            localImageRelativePath: "AnalysisPhotos/scan-latest.jpg",
            criteriaJSON: "{\"Hydration\":8}",
            debugMetadataJSON: nil,
            createdAt: latestScanSameDay
        )
        try harness.analysisRepository.saveAnalysis(
            id: "scan-day-2",
            userId: "user-1",
            score: 6.1,
            summary: "day-2",
            skinTypeDetected: "Combination",
            imageHash: "hash-day-2",
            criteriaJSON: "{\"Hydration\":7}",
            debugMetadataJSON: nil,
            createdAt: secondDay
        )

        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .guest,
            providerUserId: nil,
            email: nil,
            displayName: nil
        )

        harness.appState.refreshRecentAnalyses()

        XCTAssertEqual(harness.appState.analysisCalendarEntries.count, 2)
        XCTAssertEqual(harness.appState.analysisCalendarEntries.first?.analysisID, "scan-latest")
        XCTAssertEqual(
            harness.appState.analysisCalendarEntries.first?.localImageRelativePath,
            "AnalysisPhotos/scan-latest.jpg"
        )
    }

    func testRefreshRecentAnalysesKeepsRecentListLimitedWhileCalendarUsesFullHistory() throws {
        let harness = try makeAppStateHarness()
        let calendar = makeUTCCalendar()
        let latestDay = makeDate(year: 2026, month: 3, day: 30, hour: 18, calendar: calendar)

        for dayOffset in 0..<25 {
            try harness.analysisRepository.saveAnalysis(
                id: "scan-\(dayOffset)",
                userId: "user-1",
                score: 5.0 + Double(dayOffset) * 0.1,
                summary: "summary-\(dayOffset)",
                skinTypeDetected: "Combination",
                imageHash: "hash-\(dayOffset)",
                criteriaJSON: "{\"Hydration\":7}",
                debugMetadataJSON: nil,
                createdAt: calendar.date(byAdding: .day, value: -dayOffset, to: latestDay)
            )
        }

        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .guest,
            providerUserId: nil,
            email: nil,
            displayName: nil
        )

        harness.appState.refreshRecentAnalyses()

        XCTAssertEqual(harness.appState.recentAnalyses.count, 20)
        XCTAssertEqual(harness.appState.analysisCalendarEntries.count, 25)
        XCTAssertEqual(harness.appState.totalScanCount, 25)
    }

    func testProcessPendingAnalysisStillPersistsWhenLocalPhotoCachingFails() async throws {
        let analysisPhotoStore = AnalysisPhotoStoreMock(saveError: TestFailure.expected)
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            analysisPhotoStore: analysisPhotoStore,
            skinAnalysisService: SkinAnalysisServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "scan-success",
                    result: OnDeviceAnalysisResult(
                        score: 6.7,
                        summary: "Healthy barrier",
                        skinTypeDetected: "Combination",
                        criteria: ["Hydration": 7.1]
                    )
                )
            ),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(Data([0x01, 0x02]))

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertEqual(analysisID, "scan-success")
        let savedAnalysis = try harness.analysisRepository.analysis(byId: "scan-success")
        let saved = try XCTUnwrap(savedAnalysis)
        XCTAssertNil(saved.localImageRelativePath)
        XCTAssertEqual(harness.appState.recentAnalyses.map { $0.id }, ["scan-success"])
        XCTAssertEqual(harness.appState.analysisCalendarEntries.map { $0.analysisID }, ["scan-success"])
    }

    func testEnsureAuthenticatedScanAvailabilityKeepsUserOutOfAuthGateBeforeScan() throws {
        let harness = try makeAppStateHarness()

        let isReady = harness.appState.ensureAuthenticatedScanAvailability(redirectToAuth: true)

        XCTAssertFalse(isReady)
        XCTAssertEqual(harness.appState.currentRoute, [])
        XCTAssertNil(harness.appState.authErrorMessage)
        XCTAssertEqual(
            harness.appState.scanErrorMessage,
            "SkinLit is still preparing your local session. Try again in a moment."
        )
    }

    func testBootstrapStartsGuestFlowWhenNoStoredSessionExists() async throws {
        let harness = try makeAppStateHarness()

        await harness.appState.bootstrap()

        XCTAssertEqual(harness.authService.continueAsGuestForBootstrapCallCount, 1)
        XCTAssertEqual(harness.appState.currentSession?.provider, .guest)
        XCTAssertTrue(harness.appState.isAuthenticated)
        XCTAssertEqual(harness.appState.currentRoute, [.onboardingGender])
    }

    func testSignOutFallsBackToGuestFlowInsteadOfShowingAuthGate() async throws {
        let harness = try makeAppStateHarness()
        harness.appState.currentSession = AuthSession(
            localUserId: "signed-in-user",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.isAuthenticated = true
        harness.appState.hasCompletedOnboarding = true
        harness.appState.currentRoute = [.home]

        await harness.appState.signOut()

        XCTAssertEqual(harness.authService.continueAsGuestCallCount, 1)
        XCTAssertEqual(harness.appState.currentSession?.provider, .guest)
        XCTAssertTrue(harness.appState.isAuthenticated)
        XCTAssertEqual(harness.appState.currentRoute, [.onboardingGender])
    }

    func testAcceptCurrentScanConsentPersistsCurrentVersion() throws {
        let harness = try makeAppStateHarness()

        XCTAssertTrue(harness.appState.acceptCurrentScanConsentIfNeeded())

        XCTAssertTrue(harness.appState.hasAcceptedCurrentScanConsent)
        XCTAssertTrue(try harness.settingsRepository.hasAcceptedScanConsent(version: AppConfig.scanConsentVersion))
    }

    func testDeleteAccountFailureUsesHomeErrorMessageInsteadOfAuthErrorMessage() async throws {
        let harness = try makeAppStateHarness()
        harness.authService.deleteAccountError = AuthError.accountDeletionFailed

        await harness.appState.deleteAccount()

        XCTAssertEqual(harness.appState.homeErrorMessage, AuthError.accountDeletionFailed.localizedDescription)
        XCTAssertNil(harness.appState.authErrorMessage)
    }

    func testAppStateCanStartWithLaunchWarningMessage() throws {
        let harness = try makeAppStateHarness(launchWarningMessage: "Local data fallback active.")

        XCTAssertEqual(harness.appState.launchWarningMessage, "Local data fallback active.")

        harness.appState.dismissLaunchWarning()
        XCTAssertNil(harness.appState.launchWarningMessage)
    }

    func testLocalStoreSupportsInMemoryFallbackContainer() throws {
        let container = try LocalStore.makeContainer(storageMode: .inMemory)
        let context = ModelContext(container)
        context.insert(AppLocalSettings(id: AppLocalSettings.singletonId))

        XCTAssertNoThrow(try context.save())
    }

    func testProcessPendingAnalysisContinuesWhenLocalFaceDetectionReturnsZeroFaces() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "scan-from-zero-face-count",
                    result: OnDeviceAnalysisResult(
                        score: 6.2,
                        summary: "Recovered by remote analysis",
                        skinTypeDetected: "Combination",
                        criteria: ["Hydration": 6.8]
                    )
                )
            )
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(Data([0x00]))

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertEqual(analysisID, "scan-from-zero-face-count")
        XCTAssertEqual(harness.appState.recentAnalyses.map { $0.id }, ["scan-from-zero-face-count"])
        XCTAssertNil(harness.appState.scanErrorMessage)
        XCTAssertEqual(harness.appState.scanErrorReasons, [SkinImageQualityReason]())
    }

    func testProcessPendingAnalysisStillRejectsWhenMultipleFacesAreDetected() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            faceDetectionService: FaceDetectionServiceMock(faceCount: 2)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(Data([0x00]))

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertNil(analysisID)
        XCTAssertEqual(harness.appState.scanErrorMessage, "Use a photo with only your face in frame.")
        XCTAssertEqual(harness.appState.scanErrorReasons, [SkinImageQualityReason.multipleFaces])
    }

    func testProcessPendingAnalysisCanContinueAfterHeavyMakeupWarningAndMarksScan() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                error: SkinAnalysisRemoteError.insufficientImageQuality(
                    reasons: [.heavyMakeup, .badAngle]
                )
            ),
            qualityOverrideAnalysisService: SkinAnalysisQualityOverrideServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "override-scan",
                    result: OnDeviceAnalysisResult(
                        score: 5.9,
                        summary: "Makeup noted",
                        skinTypeDetected: "Combination",
                        criteria: [
                            "Hydration": 6.1,
                            "Texture": 5.7,
                            "Uniformity": 5.8,
                            "Luminosity": 6.0
                        ]
                    )
                )
            ),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(makeTestJPEGData(), allowCacheReuse: false)

        let firstAttempt = await harness.appState.processPendingAnalysis()

        XCTAssertNil(firstAttempt)
        XCTAssertEqual(
            harness.appState.scanErrorReasons,
            [.heavyMakeup, .badAngle]
        )
        XCTAssertTrue(harness.appState.canForceAnalyzeCurrentScan)
        XCTAssertTrue(harness.appState.acceptCurrentScanQualityWarningForManualAnalysis())

        let secondAttempt = await harness.appState.processPendingAnalysis()

        let analysisID = try XCTUnwrap(secondAttempt)
        let saved = try XCTUnwrap(harness.analysisRepository.analysis(byId: analysisID))
        let debugMetadata = try XCTUnwrap(saved.debugMetadata)
        XCTAssertTrue(debugMetadata.qualityOverrideAccepted == true)
        XCTAssertEqual(debugMetadata.qualityOverrideAcceptedReasons, [.heavyMakeup, .badAngle])
        XCTAssertEqual(debugMetadata.qualityOverrideLabel, "with makeup")
        XCTAssertEqual(debugMetadata.source, .qualityOverride)
        XCTAssertNil(harness.appState.scanErrorMessage)
        XCTAssertEqual(harness.appState.analysisCalendarEntries.first?.analysisID, analysisID)
        XCTAssertTrue(harness.appState.analysisCalendarEntries.first?.wasLoggedWithMakeup == true)
    }

    func testProcessPendingAnalysisCanContinueAfterTechnicalQualityWarning() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                error: SkinAnalysisRemoteError.insufficientImageQuality(
                    reasons: [.lowLight, .blur]
                )
            ),
            qualityOverrideAnalysisService: SkinAnalysisQualityOverrideServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "technical-override-scan",
                    result: OnDeviceAnalysisResult(
                        score: 5.4,
                        summary: "Lower confidence lighting scan",
                        skinTypeDetected: "Combination",
                        criteria: [
                            "Hydration": 5.5,
                            "Texture": 5.3,
                            "Uniformity": 5.2,
                            "Luminosity": 5.6
                        ]
                    )
                )
            ),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(makeTestJPEGData(), allowCacheReuse: false)

        let firstAttempt = await harness.appState.processPendingAnalysis()

        XCTAssertNil(firstAttempt)
        XCTAssertEqual(harness.appState.scanErrorReasons, [.lowLight, .blur])
        XCTAssertTrue(harness.appState.canForceAnalyzeCurrentScan)
        XCTAssertTrue(harness.appState.acceptCurrentScanQualityWarningForManualAnalysis())

        let secondAttempt = await harness.appState.processPendingAnalysis()

        let analysisID = try XCTUnwrap(secondAttempt)
        let saved = try XCTUnwrap(harness.analysisRepository.analysis(byId: analysisID))
        let debugMetadata = try XCTUnwrap(saved.debugMetadata)
        XCTAssertEqual(analysisID, "technical-override-scan")
        XCTAssertTrue(debugMetadata.qualityOverrideAccepted == true)
        XCTAssertEqual(debugMetadata.qualityOverrideAcceptedReasons, [.lowLight, .blur])
        XCTAssertEqual(debugMetadata.qualityOverrideLabel, "manual quality override")
    }

    func testProcessPendingAnalysisKeepsAnalyzeAnywayAvailableAfterOverrideRetryStillReturnsAcceptedReason() async throws {
        let overrideService = SequencedQualityOverrideServiceMock(results: [
            .failure(SkinAnalysisRemoteError.insufficientImageQuality(reasons: [.badAngle])),
            .success(
                SkinAnalysisOutcome(
                    analysisID: "override-after-retry",
                    result: OnDeviceAnalysisResult(
                        score: 6.1,
                        summary: "Override completed",
                        skinTypeDetected: "Combination",
                        criteria: [
                            "Hydration": 6.3,
                            "Texture": 5.9,
                            "Uniformity": 6.0,
                            "Luminosity": 6.2
                        ]
                    )
                )
            )
        ])
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                error: SkinAnalysisRemoteError.insufficientImageQuality(
                    reasons: [.heavyMakeup, .badAngle]
                )
            ),
            qualityOverrideAnalysisService: overrideService,
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(makeTestJPEGData(), allowCacheReuse: false)

        let firstAttempt = await harness.appState.processPendingAnalysis()
        XCTAssertNil(firstAttempt)
        XCTAssertTrue(harness.appState.acceptCurrentScanQualityWarningForManualAnalysis())

        let secondAttempt = await harness.appState.processPendingAnalysis()

        XCTAssertNil(secondAttempt)
        XCTAssertEqual(harness.appState.scanErrorReasons, [.badAngle])
        XCTAssertTrue(harness.appState.canForceAnalyzeCurrentScan)
        XCTAssertTrue(harness.appState.acceptCurrentScanQualityWarningForManualAnalysis())

        let thirdAttemptValue = await harness.appState.processPendingAnalysis()
        let thirdAttempt = try XCTUnwrap(thirdAttemptValue)
        XCTAssertEqual(thirdAttempt, "override-after-retry")
    }

    func testProcessPendingAnalysisParsesBackendQualityRejectionIntoStructuredReasons() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                error: BackendClientError.scanRejected(
                    message: "Photo quality is not good enough for a reliable scan. Issues: heavy_makeup, bad_angle."
                )
            ),
            qualityOverrideAnalysisService: SkinAnalysisQualityOverrideServiceMock(),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(makeTestJPEGData(), allowCacheReuse: false)

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertNil(analysisID)
        XCTAssertEqual(harness.appState.scanErrorMessage, "This selfie needs a cleaner capture before we can score it.")
        XCTAssertEqual(harness.appState.scanErrorReasons, [.heavyMakeup, .badAngle])
        XCTAssertTrue(harness.appState.canForceAnalyzeCurrentScan)
    }

    func testProcessPendingAnalysisTreatsCachedIdenticalPhotoAsFreshScan() async throws {
        let countingService = CountingSkinAnalysisServiceMock(
            outcome: SkinAnalysisOutcome(
                analysisID: "first-scan",
                result: OnDeviceAnalysisResult(
                    score: 6.8,
                    summary: "Initial remote result",
                    skinTypeDetected: "Combination",
                    criteria: [
                        "Hydration": 7.0,
                        "Texture": 6.7,
                        "Uniformity": 6.8,
                        "Luminosity": 6.9
                    ]
                )
            )
        )
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: countingService,
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )

        let imageData = makeTestJPEGData()

        harness.appState.queueScanImageData(imageData)
        let firstAnalysisID = await harness.appState.processPendingAnalysis()

        harness.appState.queueScanImageData(imageData)
        let duplicatedAnalysisID = await harness.appState.processPendingAnalysis()

        XCTAssertEqual(firstAnalysisID, "first-scan")
        XCTAssertNotNil(duplicatedAnalysisID)
        XCTAssertNotEqual(duplicatedAnalysisID, firstAnalysisID)
        XCTAssertEqual(countingService.invocationCount, 1)
        XCTAssertEqual(try harness.analysisRepository.analysisCount(userId: "user-1"), 2)
        XCTAssertEqual(Array(harness.appState.recentAnalyses.prefix(2)).map { $0.id }, [duplicatedAnalysisID!, "first-scan"])
    }

    func testProcessPendingAnalysisSharesSingleInFlightExecutionAcrossConcurrentCalls() async throws {
        let countingService = CountingSkinAnalysisServiceMock(
            outcome: SkinAnalysisOutcome(
                analysisID: "shared-scan",
                result: OnDeviceAnalysisResult(
                    score: 6.5,
                    summary: "Shared execution",
                    skinTypeDetected: "Combination",
                    criteria: [
                        "Hydration": 6.7,
                        "Texture": 6.4,
                        "Uniformity": 6.6,
                        "Luminosity": 6.5
                    ]
                )
            ),
            delayNanoseconds: 150_000_000
        )
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: countingService,
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )
        harness.appState.queueScanImageData(makeTestJPEGData())

        async let first = harness.appState.processPendingAnalysis()
        async let second = harness.appState.processPendingAnalysis()
        let firstResult = await first
        let secondResult = await second

        XCTAssertEqual(firstResult, "shared-scan")
        XCTAssertEqual(secondResult, "shared-scan")
        XCTAssertEqual(countingService.invocationCount, 1)
        XCTAssertEqual(try harness.analysisRepository.analysisCount(userId: "user-1"), 1)
    }

    func testProcessPendingAnalysisStabilizesLargeJumpAgainstRecentSimilarScans() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "scan-stabilized",
                    result: OnDeviceAnalysisResult(
                        score: 8.3,
                        summary: "Fresh result",
                        skinTypeDetected: "Combination",
                        criteria: [
                            "Hydration": 7.2,
                            "Texture": 6.9,
                            "Uniformity": 7.0,
                            "Luminosity": 7.1
                        ]
                    ),
                    debugMetadata: LocalAnalysisDebugMetadata(
                        analysisVersion: "remote-v1",
                        predictedBand: "8-10",
                        observedConditions: nil,
                        imageQualityStatus: .ok,
                        imageQualityReasons: [],
                        referenceCatalogVersion: "refs-v1",
                        finalScore: 8.3,
                        model: "gpt-5.4-mini",
                        source: .remoteFresh
                    )
                )
            ),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )

        try saveAnalysis(
            harness.analysisRepository,
            id: "recent-1",
            score: 6.2,
            createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 2),
            criteriaJSON: "{\"Hydration\":7.0,\"Texture\":6.8,\"Uniformity\":6.9,\"Luminosity\":7.1}"
        )
        try saveAnalysis(
            harness.analysisRepository,
            id: "recent-2",
            score: 6.4,
            createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 4),
            criteriaJSON: "{\"Hydration\":7.1,\"Texture\":7.0,\"Uniformity\":7.1,\"Luminosity\":7.0}"
        )

        harness.appState.queueScanImageData(Data([0x01, 0x02, 0x03]))

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertEqual(analysisID, "scan-stabilized")
        let saved = try XCTUnwrap(harness.analysisRepository.analysis(byId: "scan-stabilized"))
        XCTAssertEqual(saved.score, 7.6)
        let debugMetadata = try XCTUnwrap(saved.debugMetadata)
        XCTAssertEqual(debugMetadata.baseScore, 8.3)
        XCTAssertEqual(debugMetadata.finalScore, 7.6)
        XCTAssertEqual(debugMetadata.localStabilityAdjustmentApplied, true)
        XCTAssertEqual(debugMetadata.localStabilityNeighborCount, 2)
        XCTAssertEqual(harness.appState.recentAnalyses.first?.score, 7.6)
    }

    func testProcessPendingAnalysisKeepsRawScoreWhenSimilarHistoryIsTooWeak() async throws {
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            skinAnalysisService: SkinAnalysisServiceMock(
                outcome: SkinAnalysisOutcome(
                    analysisID: "scan-raw",
                    result: OnDeviceAnalysisResult(
                        score: 8.1,
                        summary: "Fresh result",
                        skinTypeDetected: "Combination",
                        criteria: [
                            "Hydration": 7.8,
                            "Texture": 7.6,
                            "Uniformity": 7.7,
                            "Luminosity": 7.5
                        ]
                    )
                )
            ),
            faceDetectionService: FaceDetectionServiceMock(faceCount: 1)
        )
        harness.authService.hasStoredBackendSession = true
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )

        try saveAnalysis(
            harness.analysisRepository,
            id: "older-far",
            score: 6.0,
            createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 40),
            criteriaJSON: "{\"Hydration\":4.0,\"Texture\":4.2,\"Uniformity\":4.1,\"Luminosity\":4.3}"
        )

        harness.appState.queueScanImageData(Data([0x0A, 0x0B, 0x0C]))

        let analysisID = await harness.appState.processPendingAnalysis()

        XCTAssertEqual(analysisID, "scan-raw")
        let saved = try XCTUnwrap(harness.analysisRepository.analysis(byId: "scan-raw"))
        XCTAssertEqual(saved.score, 8.1)
        XCTAssertNil(saved.debugMetadata?.localStabilityAdjustmentApplied)
    }

    func testReferralRewardMathGrantsOneBonusEveryTwoValidatedReferrals() {
        XCTAssertEqual(AppState.referralBonusScansEarned(validatedReferralCount: 0), 0)
        XCTAssertEqual(AppState.referralBonusScansEarned(validatedReferralCount: 1), 0)
        XCTAssertEqual(AppState.referralBonusScansEarned(validatedReferralCount: 2), 1)
        XCTAssertEqual(AppState.referralBonusScansEarned(validatedReferralCount: 5), 2)
    }

    func testScanGateStopsAtBaseQuotaEvenWhenReferralRewardsExist() throws {
        let harness = try makeAppStateHarness()
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )

        for index in 0..<AppState.freeScanQuota {
            harness.appState.persistAnalysis(
                id: "scan-\(index)",
                score: 6.0,
                summary: "summary-\(index)",
                skinTypeDetected: "Combination",
                imageHash: "hash-\(index)",
                criteria: ["Hydration": 6.0]
            )
        }

        harness.appState.validatedReferralCount = 4
        harness.appState.referralRewardCount = 2

        XCTAssertEqual(AppState.freeScanQuota, 10)
        XCTAssertEqual(harness.appState.totalScanCount, 10)
        XCTAssertEqual(harness.appState.totalFreeScanAllowance, 10)
        XCTAssertEqual(harness.appState.remainingFreeScans, 0)
        XCTAssertFalse(harness.appState.canRunScan)
    }

    func testScanGateDoesNotBlockFreshUserBecauseDifferentUserHasOldAnalyses() throws {
        let harness = try makeAppStateHarness()

        for index in 0..<AppState.freeScanQuota {
            try saveAnalysis(
                harness.analysisRepository,
                id: "legacy-\(index)",
                userId: "legacy-user",
                score: 5.0
            )
        }

        harness.appState.currentSession = AuthSession(
            localUserId: "fresh-user",
            provider: .apple,
            providerUserId: "apple-fresh-user",
            email: "fresh@example.com",
            displayName: "Fresh User",
            remoteUserId: "remote-fresh-user"
        )
        harness.appState.totalScanCount = try harness.analysisRepository.analysisCount(userId: "fresh-user")

        XCTAssertEqual(try harness.analysisRepository.totalAnalysisCount(), 10)
        XCTAssertEqual(harness.appState.consumedFreeScans, 0)
        XCTAssertEqual(harness.appState.remainingFreeScans, 10)
        XCTAssertTrue(harness.appState.canRunScan)
    }

    func testRefreshPaywallDataKeepsExistingPackagesWhenReloadFails() async throws {
        let billingService = BillingServiceMock(
            packages: [
                PaywallPackage(
                    id: "com.skinlit.pro.monthly",
                    title: "Monthly",
                    priceText: "$14.99",
                    trialDescription: "7-day free trial",
                    badge: "MOST POPULAR"
                )
            ]
        )
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            billingService: billingService
        )

        await harness.appState.refreshPaywallData()
        XCTAssertEqual(harness.appState.paywallPackages.count, 1)

        billingService.fetchPackagesError = BillingError.productsUnavailable

        await harness.appState.refreshPaywallData()

        XCTAssertEqual(harness.appState.paywallPackages.count, 1)
        XCTAssertEqual(
            harness.appState.billingErrorMessage,
            BillingError.productsUnavailable.localizedDescription
        )
        XCTAssertFalse(harness.appState.isPaywallPackagesLoading)
    }

    func testRefreshPaywallDataPreservesKnownProAccessWhenEntitlementRefreshFails() async throws {
        let billingService = BillingServiceMock(
            packages: [
                PaywallPackage(
                    id: "com.skinlit.pro.monthly",
                    title: "Monthly",
                    priceText: "$14.99"
                )
            ],
            entitlement: SubscriptionEntitlement(
                isActive: true,
                productId: "com.skinlit.pro.monthly",
                expirationDate: nil
            )
        )
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            billingService: billingService
        )

        await harness.appState.refreshPaywallData()
        XCTAssertTrue(harness.appState.isProActive)

        billingService.entitlementError = BillingError.productsUnavailable

        await harness.appState.refreshPaywallData()

        XCTAssertTrue(harness.appState.isProActive)
        XCTAssertEqual(harness.appState.subscriptionPlanId, "com.skinlit.pro.monthly")
        XCTAssertEqual(
            harness.appState.billingErrorMessage,
            BillingError.productsUnavailable.localizedDescription
        )
    }

    func testHandleScenePhaseRefreshesBillingStateForSignedInSession() async throws {
        let billingService = BillingServiceMock(
            entitlement: SubscriptionEntitlement(
                isActive: true,
                productId: "com.skinlit.pro.monthly",
                expirationDate: nil
            )
        )
        let harness = try makeAppStateHarness(
            launchWarningMessage: nil,
            billingService: billingService
        )
        harness.appState.currentSession = AuthSession(
            localUserId: "user-1",
            provider: .apple,
            providerUserId: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User",
            remoteUserId: "remote-user-1"
        )

        await harness.appState.handleScenePhase(.active)

        XCTAssertTrue(harness.appState.isProActive)
        XCTAssertEqual(harness.appState.subscriptionPlanId, "com.skinlit.pro.monthly")
    }

#if DEBUG
    func testDeveloperFallbackBillingServiceUsesFallbackCatalogWhenPrimaryFails() async throws {
        let primary = BillingServiceMock(
            fetchPackagesError: BillingError.productsUnavailable,
            entitlementError: BillingError.productsUnavailable
        )
        let fallback = MockBillingService(productIDs: AppConfig.subscriptionProductIds)
        let service = DeveloperFallbackBillingService(primary: primary, fallback: fallback)

        let packages = try await service.fetchPackages()
        XCTAssertEqual(
            packages.map(\.id),
            AppConfig.subscriptionProductIds
        )

        let initialEntitlement = try await service.currentEntitlement()
        XCTAssertFalse(initialEntitlement.isActive)
        let didPurchaseFallback = try await service.purchase("com.skinlit.pro.monthly")
        XCTAssertTrue(didPurchaseFallback)

        let entitlement = try await service.currentEntitlement()
        XCTAssertTrue(entitlement.isActive)
        XCTAssertEqual(entitlement.productId, "com.skinlit.pro.monthly")
    }

    func testDeveloperFallbackBillingServiceUsesPrimaryCatalogWhenAvailable() async throws {
        let primaryPackages = [
            PaywallPackage(
                id: "live.monthly",
                title: "Live Monthly",
                priceText: "$19.99",
                trialDescription: nil,
                badge: nil
            )
        ]
        let primary = BillingServiceMock(
            packages: primaryPackages,
            purchaseResult: true,
            entitlement: SubscriptionEntitlement(
                isActive: true,
                productId: "live.monthly",
                expirationDate: nil
            )
        )
        let fallback = MockBillingService(productIDs: AppConfig.subscriptionProductIds)
        let service = DeveloperFallbackBillingService(primary: primary, fallback: fallback)

        let packages = try await service.fetchPackages()
        XCTAssertEqual(packages, primaryPackages)
        let didPurchasePrimary = try await service.purchase("live.monthly")
        XCTAssertTrue(didPurchasePrimary)

        let entitlement = try await service.currentEntitlement()
        XCTAssertTrue(entitlement.isActive)
        XCTAssertEqual(entitlement.productId, "live.monthly")
    }
#endif

    private func makeRepository() throws -> AnalysisRepository {
        let schema = Schema([LocalAnalysis.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return AnalysisRepository(context: ModelContext(container))
    }

    private func makeAppStateHarness() throws -> (
        appState: AppState,
        analysisRepository: AnalysisRepository,
        settingsRepository: SettingsRepository,
        authService: AuthServiceMock
    ) {
        try makeAppStateHarness(
            launchWarningMessage: nil,
            analysisPhotoStore: AnalysisPhotoStoreMock(),
            skinAnalysisService: SkinAnalysisServiceMock(),
            faceDetectionService: FaceDetectionServiceMock()
        )
    }

    private func makeAppStateHarness(
        launchWarningMessage: String?,
        analysisPhotoStore: AnalysisPhotoStoreMock = AnalysisPhotoStoreMock(),
        billingService: BillingService = BillingServiceMock(),
        skinAnalysisService: any SkinAnalysisService = SkinAnalysisServiceMock(),
        qualityOverrideAnalysisService: (any SkinAnalysisQualityOverrideService)? = nil,
        faceDetectionService: FaceDetectionServiceMock = FaceDetectionServiceMock()
    ) throws -> (
        appState: AppState,
        analysisRepository: AnalysisRepository,
        settingsRepository: SettingsRepository,
        authService: AuthServiceMock
    ) {
        let schema = Schema([
            LocalAnalysis.self,
            OnboardingDraft.self,
            OnboardingProfile.self,
            SkinJourneyLog.self,
            AppLocalSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let analysisRepository = AnalysisRepository(context: context)
        let settingsRepository = SettingsRepository(context: context)
        let authService = AuthServiceMock()

        let appState = AppState(
            authService: authService,
            onboardingDraftRepository: OnboardingDraftRepository(context: context),
            onboardingRepository: OnboardingRepository(context: context),
            analysisRepository: analysisRepository,
            skinJourneyRepository: SkinJourneyRepository(context: context),
            analysisPhotoStore: analysisPhotoStore,
            settingsRepository: settingsRepository,
            notificationService: NotificationServiceMock(),
            billingService: billingService,
            skinAnalysisService: skinAnalysisService,
            qualityOverrideAnalysisService: qualityOverrideAnalysisService,
            faceDetectionService: faceDetectionService,
            launchWarningMessage: launchWarningMessage
        )

        return (appState, analysisRepository, settingsRepository, authService)
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func makeTestJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func saveAnalysis(
        _ repository: AnalysisRepository,
        id: String,
        userId: String = "user-1",
        score: Double,
        createdAt: Date? = nil,
        localImageRelativePath: String? = nil,
        criteriaJSON: String = "{\"Hydration\":7}"
    ) throws {
        try repository.saveAnalysis(
            id: id,
            userId: userId,
            score: score,
            summary: "summary-\(id)",
            skinTypeDetected: "Combination",
            imageHash: "hash-\(id)",
            localImageRelativePath: localImageRelativePath,
            criteriaJSON: criteriaJSON,
            debugMetadataJSON: nil,
            createdAt: createdAt
        )
    }

    private func makeCriterionInsightsJSON() throws -> String {
        let insights = [
            "Hydration": SkinCriterionInsight(
                status: "Balanced",
                summary: "Hydration looks mostly comfortable with light dryness around the cheeks.",
                positiveObservations: ["The central face does not show obvious flaking."],
                negativeObservations: ["The cheek area may be pulling the hydration score down slightly."],
                routineFocus: "Keep a barrier-supporting moisturizer consistent at night."
            )
        ]
        let data = try JSONEncoder().encode(insights)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

@MainActor
private final class AuthServiceMock: AuthService {
    var isGoogleSignInAvailable = false
    var hasStoredBackendSession = false
    var lastGuestBackendSessionErrorDescription: String? = nil
    var deleteAccountError: Error?
    var restoreSessionResult: AuthSession?
    var continueAsGuestForBootstrapCallCount = 0
    var continueAsGuestCallCount = 0

    func restoreSession() async -> AuthSession? { restoreSessionResult }

    func continueAsGuestForBootstrap() async throws -> AuthSession {
        continueAsGuestForBootstrapCallCount += 1
        return AuthSession(localUserId: "user-1", provider: .guest, providerUserId: nil, email: nil, displayName: nil)
    }

    func signInWithApple(result: Result<ASAuthorization, Error>) async throws -> AuthSession {
        throw AuthError.cancelled
    }

    func signInWithGoogle() async throws -> AuthSession {
        throw AuthError.googleNotConfigured
    }

    func continueAsGuest() async throws -> AuthSession {
        continueAsGuestCallCount += 1
        return AuthSession(localUserId: "user-1", provider: .guest, providerUserId: nil, email: nil, displayName: nil)
    }

    func signOut() async throws {}

    func deleteAccount() async throws {
        if let deleteAccountError {
            throw deleteAccountError
        }
    }
}

private final class NotificationServiceMock: NotificationService {
    func refreshAuthorizationStatus() async -> NotificationAuthorizationStatus { .notDetermined }
    func requestAuthorization() async -> NotificationPromptState { .neverAsked }
    func rescheduleReengagementNotifications(context: ReengagementContext) async {}
    func cancelReengagementNotifications() async {}
    func consumePendingOpenIntent() -> NotificationOpenIntent? { nil }
}

private final class BillingServiceMock: BillingService {
    var packages: [PaywallPackage]
    var fetchPackagesError: Error?
    var purchaseResult: Bool
    var purchaseError: Error?
    var restoreResult: Bool
    var restoreError: Error?
    var entitlement: SubscriptionEntitlement
    var entitlementError: Error?

    init(
        packages: [PaywallPackage] = [],
        fetchPackagesError: Error? = nil,
        purchaseResult: Bool = false,
        purchaseError: Error? = nil,
        restoreResult: Bool = false,
        restoreError: Error? = nil,
        entitlement: SubscriptionEntitlement = SubscriptionEntitlement(
            isActive: false,
            productId: nil,
            expirationDate: nil
        ),
        entitlementError: Error? = nil
    ) {
        self.packages = packages
        self.fetchPackagesError = fetchPackagesError
        self.purchaseResult = purchaseResult
        self.purchaseError = purchaseError
        self.restoreResult = restoreResult
        self.restoreError = restoreError
        self.entitlement = entitlement
        self.entitlementError = entitlementError
    }

    func fetchPackages() async throws -> [PaywallPackage] {
        if let fetchPackagesError {
            throw fetchPackagesError
        }
        return packages
    }

    func purchase(_ packageId: String) async throws -> Bool {
        if let purchaseError {
            throw purchaseError
        }
        return purchaseResult
    }

    func restore() async throws -> Bool {
        if let restoreError {
            throw restoreError
        }
        return restoreResult
    }

    func currentEntitlement() async throws -> SubscriptionEntitlement {
        if let entitlementError {
            throw entitlementError
        }
        return entitlement
    }
}

private enum TestFailure: Error {
    case expected
}

private final class AnalysisPhotoStoreMock: AnalysisPhotoStoring {
    let saveError: Error?
    private(set) var savedImageData: [String: Data] = [:]
    private(set) var deletedRelativePaths: [String] = []

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func saveProcessedPhoto(_ imageData: Data, analysisID: String) throws -> String {
        if let saveError {
            throw saveError
        }
        savedImageData[analysisID] = imageData
        return "AnalysisPhotos/\(analysisID).jpg"
    }

    func deletePhoto(relativePath: String) throws {
        deletedRelativePaths.append(relativePath)
    }

    func fileURL(forRelativePath relativePath: String) -> URL? {
        URL(fileURLWithPath: "/tmp/\(relativePath)")
    }
}

private struct SkinAnalysisServiceMock: SkinAnalysisService {
    let outcome: SkinAnalysisOutcome
    let error: Error?

    init(
        outcome: SkinAnalysisOutcome = SkinAnalysisOutcome(
            analysisID: "mock-analysis",
            result: OnDeviceAnalysisResult(
                score: 0,
                summary: "mock",
                skinTypeDetected: "Unknown",
                criteria: [:]
            )
        ),
        error: Error? = nil
    ) {
        self.outcome = outcome
        self.error = error
    }

    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome {
        if let error {
            throw error
        }
        return outcome
    }
}

private struct SkinAnalysisQualityOverrideServiceMock: SkinAnalysisQualityOverrideService {
    let isConfigured: Bool
    let outcome: SkinAnalysisOutcome
    let error: Error?

    init(
        isConfigured: Bool = true,
        outcome: SkinAnalysisOutcome = SkinAnalysisOutcome(
            analysisID: "override-analysis",
            result: OnDeviceAnalysisResult(
                score: 0,
                summary: "override",
                skinTypeDetected: "Unknown",
                criteria: [:]
            )
        ),
        error: Error? = nil
    ) {
        self.isConfigured = isConfigured
        self.outcome = outcome
        self.error = error
    }

    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?,
        ignoredQualityReasons: Set<SkinImageQualityReason>
    ) async throws -> SkinAnalysisOutcome {
        if let error {
            throw error
        }
        return outcome
    }
}

@MainActor
private final class SequencedQualityOverrideServiceMock: SkinAnalysisQualityOverrideService {
    let isConfigured: Bool
    private var results: [Result<SkinAnalysisOutcome, Error>]

    init(
        isConfigured: Bool = true,
        results: [Result<SkinAnalysisOutcome, Error>]
    ) {
        self.isConfigured = isConfigured
        self.results = results
    }

    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?,
        ignoredQualityReasons: Set<SkinImageQualityReason>
    ) async throws -> SkinAnalysisOutcome {
        guard !results.isEmpty else {
            throw SkinAnalysisRemoteError.insufficientImageQuality(reasons: [.badAngle])
        }

        let next = results.removeFirst()
        switch next {
        case .success(let outcome):
            return outcome
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class CountingSkinAnalysisServiceMock: SkinAnalysisService {
    private(set) var invocationCount = 0
    let outcome: SkinAnalysisOutcome
    let delayNanoseconds: UInt64

    init(outcome: SkinAnalysisOutcome, delayNanoseconds: UInt64 = 0) {
        self.outcome = outcome
        self.delayNanoseconds = delayNanoseconds
    }

    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome {
        invocationCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return outcome
    }
}

private struct FaceDetectionServiceMock: FaceDetectionService {
    let faceCount: Int
    let error: Error?

    init(faceCount: Int = 0, error: Error? = nil) {
        self.faceCount = faceCount
        self.error = error
    }

    func detectFaceCount(in imageData: Data) async throws -> Int {
        if let error {
            throw error
        }
        return faceCount
    }
}
