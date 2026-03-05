import SwiftData
import UIKit
import XCTest
@testable import SkinScore

@MainActor
final class SettingsRepositoryTests: XCTestCase {
    func testNotificationPromptStateRoundTrips() throws {
        let (repository, _) = try makeRepository()

        try repository.setNotificationPromptState(.softDeclined, promptedAt: .now)

        XCTAssertEqual(try repository.notificationPromptState(), .softDeclined)
    }

    func testLastActiveAtRoundTrips() throws {
        let (repository, _) = try makeRepository()
        let expectedDate = Date(timeIntervalSince1970: 1_736_000_000)

        try repository.setLastActiveAt(expectedDate)

        XCTAssertEqual(try repository.lastActiveAt(), expectedDate)
    }

    func testSettingsRepairsSingletonAndRemovesDuplicates() throws {
        let (repository, context) = try makeRepository()
        let strayPrimary = AppLocalSettings(id: "legacy-settings")
        let strayDuplicate = AppLocalSettings(id: "stale-settings")
        context.insert(strayPrimary)
        context.insert(strayDuplicate)
        try context.save()

        try repository.setCurrentUser(id: "guest-1", provider: .guest)

        let allSettings = try context.fetch(FetchDescriptor<AppLocalSettings>())
        XCTAssertEqual(allSettings.count, 1)
        XCTAssertEqual(allSettings.first?.id, AppLocalSettings.singletonId)
        XCTAssertEqual(allSettings.first?.currentUserId, "guest-1")
        XCTAssertEqual(allSettings.first?.lastSignedInProviderRaw, AuthProvider.guest.rawValue)
    }

    private func makeRepository() throws -> (SettingsRepository, ModelContext) {
        let schema = Schema([AppLocalSettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return (SettingsRepository(context: context), context)
    }
}

final class ConvexBackendClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.responseQueue = []
        MockURLProtocol.observedRequests = []
    }

    func testExchangeSessionBuildsProviderPayload() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "session_token": "sess_123",
                    "user_id": "remote_user_1",
                    "expires_at": "2026-03-03T12:00:00Z"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        let backendSession = try await client.exchangeSession(
            provider: .google,
            providerToken: "google-token",
            providerUserID: "google-user-1",
            email: "skin@example.com",
            displayName: "Skin User"
        )

        XCTAssertEqual(backendSession.sessionToken, "sess_123")
        XCTAssertEqual(backendSession.userID, "remote_user_1")

        let request = try XCTUnwrap(MockURLProtocol.observedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://backend.example/v1/session/exchange")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let json = try requestJSON(request)
        XCTAssertEqual(json["provider"] as? String, "google")
        XCTAssertEqual(json["provider_token"] as? String, "google-token")
        XCTAssertEqual(json["provider_user_id"] as? String, "google-user-1")
        XCTAssertEqual(json["email"] as? String, "skin@example.com")
        XCTAssertEqual(json["display_name"] as? String, "Skin User")
    }

    func testCreateScanJobUsesMultipartUploadAndAuthorization() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "job_id": "job_123",
                    "status": "queued"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        let jobID = try await client.createScanJob(
            sessionToken: "sess_123",
            rawImageData: try makeJPEGData(),
            normalizedImageData: try makeJPEGData(),
            imageHash: "img_hash_1",
            userContext: SkinAnalysisUserContext(
                skinTypes: ["Combination", "Sensitive"],
                goal: "Glow",
                routineLevel: "Basic"
            )
        )

        XCTAssertEqual(jobID, "job_123")

        let request = try XCTUnwrap(MockURLProtocol.observedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://backend.example/v1/scans")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sess_123")

        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.contains("multipart/form-data; boundary="))

        let body = String(decoding: try XCTUnwrap(requestBody(from: request)), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"selfie_raw_face\""))
        XCTAssertTrue(body.contains("name=\"selfie_normalized_face\""))
        XCTAssertTrue(body.contains("name=\"input_image_hash\""))
        XCTAssertTrue(body.contains("img_hash_1"))
        XCTAssertTrue(body.contains("name=\"user_context\""))
        XCTAssertTrue(body.contains("\"skin_types\":[\"Combination\",\"Sensitive\"]"))
    }

    func testFetchScanDecodesStructuredResult() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "id": "scan_123",
                    "score": 5.8,
                    "summary": "Texture and redness stand out",
                    "skin_type_detected": "Combination",
                    "criteria": [
                        "Hydration": 7.4,
                        "Texture": 6.8,
                        "Uniformity": 6.7,
                        "Luminosity": 7.1
                    ],
                    "observed_conditions": [
                        "active_inflammation": "moderate",
                        "scarring_pitting": "mild",
                        "texture_irregularity": "moderate",
                        "redness_irritation": "mild",
                        "dryness_flaking": "none"
                    ],
                    "predicted_band": "2-4",
                    "image_quality_status": "ok",
                    "image_quality_reasons": [],
                    "analysis_version": "skin-score-v2",
                    "reference_catalog_version": "catalog-v1",
                    "model": "gpt-5-mini",
                    "created_at": "2026-03-03T12:00:00Z"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        let scan = try await client.fetchScan(sessionToken: "sess_123", scanID: "scan_123")

        XCTAssertEqual(scan.id, "scan_123")
        XCTAssertEqual(scan.score, 5.8)
        XCTAssertEqual(scan.skinTypeDetected, "Combination")
        XCTAssertEqual(scan.predictedBand, "2-4")
        XCTAssertEqual(scan.observedConditions.activeInflammation, .moderate)
        XCTAssertEqual(scan.imageQualityStatus, .ok)
    }

    func testSkinScoreComputationCapsSevereCasesAggressively() {
        let score = SkinScoreComputation.finalScore(
            criteria: [
                "Hydration": 7.8,
                "Texture": 5.9,
                "Uniformity": 5.4,
                "Luminosity": 7.2
            ],
            observedConditions: SkinObservedConditions(
                activeInflammation: .severe,
                scarringPitting: .moderate,
                textureIrregularity: .moderate,
                rednessIrritation: .moderate,
                drynessFlaking: .none
            )
        )

        XCTAssertEqual(score, 3.5)
    }

    func testUnauthorizedResponseMapsToUnauthorizedError() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 401,
                jsonObject: [
                    "error": "unauthorized",
                    "message": "Valid backend session required."
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        do {
            _ = try await client.fetchScans(sessionToken: "sess_123")
            XCTFail("Expected unauthorized error.")
        } catch let error as BackendClientError {
            switch error {
            case .unauthorized:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(requestBody(from: request))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data.isEmpty ? nil : data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseQueue: [MockHTTPResponse] = []
    static var observedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.observedRequests.append(request)

        guard !Self.responseQueue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = Self.responseQueue.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct MockHTTPResponse {
    let statusCode: Int
    let body: Data

    static func success(statusCode: Int, jsonObject: [String: Any]) -> MockHTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data("{}".utf8)
        return MockHTTPResponse(statusCode: statusCode, body: body)
    }
}
