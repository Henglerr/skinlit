import XCTest
@testable import SkinScore

final class CompositeSkinAnalysisServiceTests: XCTestCase {
    func testDelegatesToRemoteAnalyzer() async throws {
        let expected = SkinAnalysisOutcome(
            analysisID: "scan_123",
            result: OnDeviceAnalysisResult(
                score: 4.2,
                summary: "Texture and tone need work",
                skinTypeDetected: "Combination",
                criteria: [
                    "Hydration": 5.1,
                    "Texture": 3.6,
                    "Uniformity": 3.9,
                    "Luminosity": 4.3
                ]
            )
        )
        let service = CompositeSkinAnalysisService(
            remoteRepository: RemoteStub(result: .success(expected))
        )

        let result = try await service.analyze(
            imageData: Data([0x01]),
            imageHash: "hash-1",
            userContext: nil
        )

        XCTAssertEqual(result.analysisID, expected.analysisID)
        XCTAssertEqual(result.result.score, expected.result.score)
        XCTAssertEqual(result.result.summary, expected.result.summary)
        XCTAssertEqual(result.result.skinTypeDetected, expected.result.skinTypeDetected)
        XCTAssertEqual(result.result.criteria, expected.result.criteria)
    }

    func testPropagatesBackendErrorsWithoutFallback() async {
        let service = CompositeSkinAnalysisService(
            remoteRepository: RemoteStub(result: .failure(BackendClientError.backendNotConfigured))
        )

        do {
            _ = try await service.analyze(imageData: Data(), imageHash: nil, userContext: nil)
            XCTFail("Expected backendNotConfigured to be thrown.")
        } catch let error as BackendClientError {
            switch error {
            case .backendNotConfigured:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct RemoteStub: RemoteScanAnalyzing {
    let result: Result<SkinAnalysisOutcome, Error>

    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome {
        try result.get()
    }
}
