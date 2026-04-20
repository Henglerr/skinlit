import SwiftData
import UIKit
import XCTest
@testable import SkinLit

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

    func testScanConsentVersionRepromptsWhenVersionChanges() throws {
        let (repository, _) = try makeRepository()

        try repository.setScanConsentAccepted(version: "consent-v1", acceptedAt: .now)

        XCTAssertTrue(try repository.hasAcceptedScanConsent(version: "consent-v1"))
        XCTAssertFalse(try repository.hasAcceptedScanConsent(version: "consent-v2"))
        XCTAssertNotNil(try repository.scanConsentAcceptedAt())
    }

    func testReferralStateRoundTripsThroughSettings() throws {
        let (repository, _) = try makeRepository()

        try repository.setPendingReferralCode("GLOW1234")
        _ = try repository.incrementReferralShareCount()
        try repository.saveReferralStatus(
            RemoteReferralStatus(
                inviteCode: "INVITE42",
                inviteURLString: "https://skinlit.lat/r/INVITE42",
                claimedCode: "GLOW1234",
                validatedReferralCount: 2,
                pendingReferralCount: 1,
                rewardCount: 1,
                updatedAt: .now
            )
        )

        let state = try repository.referralState()
        XCTAssertEqual(state.pendingCode, "GLOW1234")
        XCTAssertEqual(state.shareCount, 1)
        XCTAssertEqual(state.validatedReferralCount, 2)
        XCTAssertEqual(state.rewardCount, 1)
        XCTAssertEqual(state.claimedCode, "GLOW1234")
        XCTAssertEqual(state.inviteCode, "INVITE42")
        XCTAssertEqual(state.inviteURLString, "https://skinlit.lat/r/INVITE42")
    }

    func testInstallationIDPersistsInKeychainStore() {
        let service = "unit-test-installation-\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        let expectedAccount = "skinlit_installation_id"

        let first = AppConfig.installationID(keychainStore: store)
        let second = AppConfig.installationID(keychainStore: store)

        addTeardownBlock {
            store.delete(account: expectedAccount)
        }

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first))
    }

    func testClearCachedReferralStatusAlsoClearsPendingCode() throws {
        let (repository, _) = try makeRepository()

        try repository.setPendingReferralCode("GLOW1234")
        _ = try repository.incrementReferralShareCount()
        try repository.saveReferralStatus(
            RemoteReferralStatus(
                inviteCode: "INVITE42",
                inviteURLString: "https://skinlit.lat/r/INVITE42",
                claimedCode: "GLOW1234",
                validatedReferralCount: 2,
                pendingReferralCount: 1,
                rewardCount: 1,
                updatedAt: .now
            )
        )

        try repository.clearCachedReferralStatus()

        let state = try repository.referralState()
        XCTAssertNil(state.pendingCode)
        XCTAssertEqual(state.shareCount, 0)
        XCTAssertEqual(state.validatedReferralCount, 0)
        XCTAssertEqual(state.rewardCount, 0)
        XCTAssertNil(state.claimedCode)
        XCTAssertNil(state.inviteCode)
        XCTAssertNil(state.inviteURLString)
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
            session: session,
            installationID: "install_123"
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
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SkinLit-Installation-ID"), "install_123")

        let json = try requestJSON(request)
        XCTAssertEqual(json["provider"] as? String, "google")
        XCTAssertEqual(json["provider_token"] as? String, "google-token")
        XCTAssertEqual(json["provider_user_id"] as? String, "google-user-1")
        XCTAssertEqual(json["email"] as? String, "skin@example.com")
        XCTAssertEqual(json["display_name"] as? String, "Skin User")
        XCTAssertEqual(json["installation_id"] as? String, "install_123")
    }

    func testExchangeSessionIncludesAuthorizationCodeWhenProvided() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "session_token": "sess_abc",
                    "user_id": "remote_user_2",
                    "expires_at": "2026-03-03T12:00:00Z"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session,
            installationID: "install_456"
        )

        _ = try await client.exchangeSession(
            provider: .apple,
            providerToken: "apple-id-token",
            providerAuthorizationCode: "apple-auth-code",
            providerUserID: "apple-user-1",
            email: "skin@example.com",
            displayName: "Skin User"
        )

        let request = try XCTUnwrap(MockURLProtocol.observedRequests.first)
        let json = try requestJSON(request)
        XCTAssertEqual(json["authorization_code"] as? String, "apple-auth-code")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SkinLit-Installation-ID"), "install_456")
        XCTAssertEqual(json["installation_id"] as? String, "install_456")
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
            session: session,
            installationID: "install_789"
        )

        let response = try await client.createScanJob(
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

        XCTAssertEqual(response.jobID, "job_123")
        XCTAssertEqual(response.status, .queued)

        let request = try XCTUnwrap(MockURLProtocol.observedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://backend.example/v1/scans")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sess_123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SkinLit-Installation-ID"), "install_789")

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

    func testCreateScanJobSendsAcceptedQualityReasonsForManualOverride() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "job_id": "job_override",
                    "status": "queued"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session,
            installationID: "install_override"
        )

        _ = try await client.createScanJob(
            sessionToken: "sess_override",
            rawImageData: try makeJPEGData(),
            normalizedImageData: nil,
            imageHash: "img_hash_override",
            userContext: nil,
            ignoredQualityReasons: [.badAngle, .heavyMakeup]
        )

        let request = try XCTUnwrap(MockURLProtocol.observedRequests.first)
        let body = String(decoding: try XCTUnwrap(requestBody(from: request)), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"ignored_quality_reasons\""))
        XCTAssertTrue(body.contains("[\"heavy_makeup\",\"bad_angle\"]"))
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
        XCTAssertNil(scan.criterionInsights)
    }

    func testFetchScanDecodesCriterionInsightsWhenPresent() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "id": "scan_456",
                    "score": 7.1,
                    "summary": "The skin looks hydrated, with mild texture variation around the cheeks. Luminosity is even enough to read clearly, while redness remains limited.",
                    "skin_type_detected": "Combination",
                    "criteria": [
                        "Hydration": 7.4,
                        "Texture": 6.8,
                        "Uniformity": 6.7,
                        "Luminosity": 7.1
                    ],
                    "criterion_insights": [
                        "Hydration": [
                            "status": "Balanced",
                            "summary": "Hydration looks mostly comfortable with light dryness around the cheeks.",
                            "positive_observations": [
                                "The central face does not show obvious flaking."
                            ],
                            "negative_observations": [
                                "The cheek area may be pulling the hydration score down slightly."
                            ],
                            "routine_focus": "Keep a barrier-supporting moisturizer consistent at night."
                        ],
                        "Luminosity": [
                            "status": "Clear",
                            "summary": "Luminosity appears even across the visible face, with only minor dullness near shadowed areas.",
                            "positive_observations": [
                                "The forehead and central cheeks reflect light evenly."
                            ],
                            "negative_observations": [
                                "The lower cheek shadows make glow look slightly muted."
                            ],
                            "routine_focus": "Use gentle exfoliation only if the skin is not irritated."
                        ],
                        "Texture": [
                            "status": "Slightly uneven",
                            "summary": "Texture is generally smooth, but small bumps and pore visibility are noticeable in the cheek area.",
                            "positive_observations": [
                                "The forehead looks relatively smooth."
                            ],
                            "negative_observations": [
                                "Visible pores on the cheeks reduce the texture score."
                            ],
                            "routine_focus": "Prioritize calming actives before strong resurfacing."
                        ],
                        "Uniformity": [
                            "status": "Mild variation",
                            "summary": "Tone is mostly consistent, with mild redness variation around the cheeks and nose.",
                            "positive_observations": [
                                "No major dark patches are visible."
                            ],
                            "negative_observations": [
                                "Cheek redness creates some unevenness."
                            ],
                            "routine_focus": "Focus on daily sunscreen and redness support."
                        ]
                    ],
                    "observed_conditions": [
                        "active_inflammation": "mild",
                        "scarring_pitting": "none",
                        "texture_irregularity": "mild",
                        "redness_irritation": "mild",
                        "dryness_flaking": "none"
                    ],
                    "predicted_band": "6-8",
                    "image_quality_status": "ok",
                    "image_quality_reasons": [],
                    "analysis_version": "skin-score-v6-category-insights",
                    "reference_catalog_version": "catalog-v2",
                    "model": "gpt-5-mini",
                    "created_at": "2026-03-03T12:00:00Z"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        let scan = try await client.fetchScan(sessionToken: "sess_123", scanID: "scan_456")
        let hydration = try XCTUnwrap(scan.criterionInsights?["Hydration"])

        XCTAssertEqual(scan.criterionInsights?.count, 4)
        XCTAssertEqual(hydration.status, "Balanced")
        XCTAssertEqual(hydration.positiveObservations, ["The central face does not show obvious flaking."])
        XCTAssertEqual(hydration.negativeObservations, ["The cheek area may be pulling the hydration score down slightly."])
        XCTAssertEqual(hydration.routineFocus, "Keep a barrier-supporting moisturizer consistent at night.")

        let analysisResult = scan.asAnalysisResult
        XCTAssertEqual(analysisResult.criterionInsights?["Hydration"], hydration)
    }

    func testFetchScanDecodesComplementaryVerificationMetadata() async throws {
        let session = makeSession()
        MockURLProtocol.responseQueue = [
            .success(
                statusCode: 200,
                jsonObject: [
                    "id": "scan_987",
                    "score": 7.2,
                    "summary": "Balanced tone with minor texture",
                    "skin_type_detected": "Combination",
                    "criteria": [
                        "Hydration": 7.1,
                        "Texture": 7.0,
                        "Uniformity": 7.3,
                        "Luminosity": 7.4
                    ],
                    "observed_conditions": [
                        "active_inflammation": "mild",
                        "scarring_pitting": "none",
                        "texture_irregularity": "mild",
                        "redness_irritation": "none",
                        "dryness_flaking": "none"
                    ],
                    "predicted_band": "6-8",
                    "image_quality_status": "ok",
                    "image_quality_reasons": [],
                    "analysis_version": "skin-score-v5-reference-verified-complementary",
                    "reference_catalog_version": "catalog-v2",
                    "base_score": 6.6,
                    "verified_score": 7.2,
                    "adjustment_delta": 0.6,
                    "matched_reference_ids": ["ref-018", "ref-019"],
                    "verification_verdict": "adjust_up",
                    "adjustment_reason": "The current score was slightly low versus the matched good-skin anchors.",
                    "model": "gpt-5-mini",
                    "created_at": "2026-03-03T12:00:00Z"
                ]
            )
        ]

        let client = ConvexBackendClient(
            baseURLString: "https://backend.example",
            session: session
        )

        let scan = try await client.fetchScan(sessionToken: "sess_123", scanID: "scan_987")

        XCTAssertEqual(scan.baseScore, 6.6)
        XCTAssertEqual(scan.verifiedScore, 7.2)
        XCTAssertEqual(scan.adjustmentDelta, 0.6)
        XCTAssertEqual(scan.matchedReferenceIDs ?? [], ["ref-018", "ref-019"])
        XCTAssertEqual(scan.verificationVerdict, .adjustUp)
        XCTAssertEqual(scan.adjustmentReason, "The current score was slightly low versus the matched good-skin anchors.")

        let debugMetadata = scan.debugMetadata(source: .remoteFresh)
        XCTAssertEqual(debugMetadata.baseScore, 6.6)
        XCTAssertEqual(debugMetadata.finalScore, 7.2)
        XCTAssertEqual(debugMetadata.adjustmentDelta, 0.6)
        XCTAssertEqual(debugMetadata.matchedReferenceIDs ?? [], ["ref-018", "ref-019"])
        XCTAssertEqual(debugMetadata.verificationVerdict, .adjustUp)
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
