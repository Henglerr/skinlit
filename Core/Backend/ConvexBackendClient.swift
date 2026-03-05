import Foundation

public final class ConvexBackendClient {
    private let baseURLString: String
    private let session: URLSession

    public var isConfigured: Bool {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }

    public init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.baseURLString = AppConfig.backendBaseURL(bundle: bundle)
        self.session = session
    }

    init(baseURLString: String, session: URLSession = .shared) {
        self.baseURLString = baseURLString
        self.session = session
    }

    public func exchangeSession(
        provider: AuthProvider,
        providerToken: String,
        providerUserID: String?,
        email: String?,
        displayName: String?
    ) async throws -> BackendSession {
        var payload: [String: Any] = [
            "provider": provider.rawValue,
            "provider_token": providerToken,
            "device_label": AppConfig.deviceLabel(),
            "app_version": AppConfig.appVersion()
        ]
        if let providerUserID {
            payload["provider_user_id"] = providerUserID
        }
        if let email {
            payload["email"] = email
        }
        if let displayName {
            payload["display_name"] = displayName
        }
        return try await performJSONRequest(
            path: "/v1/session/exchange",
            method: "POST",
            bodyObject: payload,
            sessionToken: nil
        )
    }

    public func refreshSession(sessionToken: String) async throws -> BackendSession {
        try await performJSONRequest(
            path: "/v1/session/refresh",
            method: "POST",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func revokeSession(sessionToken: String) async throws {
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/session/revoke",
            method: "POST",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func fetchOnboarding(sessionToken: String) async throws -> RemoteOnboardingProfile? {
        try await performOptionalJSONRequest(
            path: "/v1/onboarding",
            method: "GET",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func saveOnboarding(
        sessionToken: String,
        skinTypes: [String],
        goal: String,
        routineLevel: String
    ) async throws {
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/onboarding",
            method: "PUT",
            bodyObject: [
                "skin_types": skinTypes,
                "goal": goal,
                "routine_level": routineLevel
            ],
            sessionToken: sessionToken
        )
    }

    public func createScanJob(
        sessionToken: String,
        rawImageData: Data,
        normalizedImageData: Data?,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        appendMultipartField(
            name: "input_image_hash",
            value: imageHash,
            boundary: boundary,
            body: &body
        )
        if let userContext {
            let payload = try JSONEncoder.backendEncoder.encode(userContext)
            let value = String(data: payload, encoding: .utf8)
            appendMultipartField(
                name: "user_context",
                value: value,
                boundary: boundary,
                body: &body
            )
        }
        appendMultipartFile(
            name: "selfie_raw_face",
            filename: "selfie_raw_face.jpg",
            mimeType: "image/jpeg",
            data: rawImageData,
            boundary: boundary,
            body: &body
        )
        if let normalizedImageData {
            appendMultipartFile(
                name: "selfie_normalized_face",
                filename: "selfie_normalized_face.jpg",
                mimeType: "image/jpeg",
                data: normalizedImageData,
                boundary: boundary,
                body: &body
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        struct CreateJobResponse: Decodable {
            let jobID: String
            enum CodingKeys: String, CodingKey { case jobID = "job_id" }
        }

        let response: CreateJobResponse = try await performRequest(
            path: "/v1/scans",
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)",
            body: body,
            sessionToken: sessionToken
        )
        return response.jobID
    }

    public func fetchScanJob(sessionToken: String, jobID: String) async throws -> RemoteScanJob {
        try await performJSONRequest(
            path: "/v1/scan-jobs/\(jobID)",
            method: "GET",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func fetchScan(sessionToken: String, scanID: String) async throws -> RemoteScanResult {
        try await performJSONRequest(
            path: "/v1/scans/\(scanID)",
            method: "GET",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func fetchScans(sessionToken: String) async throws -> [RemoteScanResult] {
        try await performJSONRequest(
            path: "/v1/scans",
            method: "GET",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func importScans(sessionToken: String, scans: [RemoteScanImportItem]) async throws {
        let payloadScans: [[String: Any]] = scans.map { scan in
            var payload: [String: Any] = [
                "clientScanId": scan.clientScanId,
                "score": scan.score,
                "summary": scan.summary,
                "skinTypeDetected": scan.skinTypeDetected,
                "criteria": scan.criteria,
                "observedConditions": [
                    "active_inflammation": scan.observedConditions.activeInflammation.rawValue,
                    "scarring_pitting": scan.observedConditions.scarringPitting.rawValue,
                    "texture_irregularity": scan.observedConditions.textureIrregularity.rawValue,
                    "redness_irritation": scan.observedConditions.rednessIrritation.rawValue,
                    "dryness_flaking": scan.observedConditions.drynessFlaking.rawValue
                ],
                "predictedBand": scan.predictedBand,
                "imageQualityStatus": scan.imageQualityStatus.rawValue,
                "imageQualityReasons": scan.imageQualityReasons.map(\.rawValue),
                "analysisVersion": scan.analysisVersion,
                "referenceCatalogVersion": scan.referenceCatalogVersion,
                "model": scan.model,
                "createdAt": ISO8601DateFormatter.backend.date(from: scan.createdAt)?.timeIntervalSince1970.millisecondsSince1970 ?? 0
            ]
            if let inputImageHash = scan.inputImageHash {
                payload["inputImageHash"] = inputImageHash
            }
            return payload
        }
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/scans/import",
            method: "POST",
            bodyObject: ["scans": payloadScans],
            sessionToken: sessionToken
        )
    }

    public func fetchJourney(sessionToken: String) async throws -> [RemoteJourneyLog] {
        try await performJSONRequest(
            path: "/v1/journey",
            method: "GET",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func upsertJourneyLog(sessionToken: String, log: RemoteJourneyLog) async throws {
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/journey/\(log.dayKey)",
            method: "PUT",
            bodyObject: [
                "day_start_at": ISO8601DateFormatter.backend.string(from: log.dayStartAt),
                "routine_step_ids": log.routineStepIDs,
                "treatment_ids": log.treatmentIDs,
                "skin_status_ids": log.skinStatusIDs,
                "note": log.note
            ],
            sessionToken: sessionToken
        )
    }

    public func deleteJourneyLog(sessionToken: String, dayKey: String) async throws {
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/journey/\(dayKey)",
            method: "DELETE",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    public func importJourney(sessionToken: String, logs: [RemoteJourneyImportItem]) async throws {
        let payloadLogs: [[String: Any]] = logs.map { log in
            [
                "dayKey": log.dayKey,
                "dayStartAt": ISO8601DateFormatter.backend.date(from: log.dayStartAt)?.timeIntervalSince1970.millisecondsSince1970 ?? 0,
                "routineStepIDs": log.routineStepIDs,
                "treatmentIDs": log.treatmentIDs,
                "skinStatusIDs": log.skinStatusIDs,
                "note": log.note,
                "createdAt": ISO8601DateFormatter.backend.date(from: log.createdAt)?.timeIntervalSince1970.millisecondsSince1970 ?? 0,
                "updatedAt": ISO8601DateFormatter.backend.date(from: log.updatedAt)?.timeIntervalSince1970.millisecondsSince1970 ?? 0
            ]
        }
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/journey/import",
            method: "POST",
            bodyObject: ["logs": payloadLogs],
            sessionToken: sessionToken
        )
    }

    public func deleteAccount(sessionToken: String) async throws {
        let _: [String: Bool] = try await performJSONRequest(
            path: "/v1/account",
            method: "DELETE",
            bodyObject: nil,
            sessionToken: sessionToken
        )
    }

    private func performJSONRequest<T: Decodable>(
        path: String,
        method: String,
        bodyObject: Any?,
        sessionToken: String?
    ) async throws -> T {
        let bodyData = try bodyObject.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await performRequest(
            path: path,
            method: method,
            contentType: bodyData == nil ? nil : "application/json",
            body: bodyData,
            sessionToken: sessionToken
        )
    }

    private func performOptionalJSONRequest<T: Decodable>(
        path: String,
        method: String,
        bodyObject: Any?,
        sessionToken: String?
    ) async throws -> T? {
        let bodyData = try bodyObject.map { try JSONSerialization.data(withJSONObject: $0) }
        let request = try makeRequest(
            path: path,
            method: method,
            contentType: bodyData == nil ? nil : "application/json",
            body: bodyData,
            sessionToken: sessionToken
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        if httpResponse.statusCode == 200, data.trimmingWhitespaceJSON == "null" {
            return nil
        }
        try validate(httpResponse: httpResponse, data: data)
        return try JSONDecoder.backendDecoder.decode(T.self, from: data)
    }

    private func performRequest<T: Decodable>(
        path: String,
        method: String,
        contentType: String?,
        body: Data?,
        sessionToken: String?
    ) async throws -> T {
        let request = try makeRequest(
            path: path,
            method: method,
            contentType: contentType,
            body: body,
            sessionToken: sessionToken
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        try validate(httpResponse: httpResponse, data: data)
        return try JSONDecoder.backendDecoder.decode(T.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        contentType: String?,
        body: Data?,
        sessionToken: String?
    ) throws -> URLRequest {
        guard isConfigured else {
            throw BackendClientError.backendNotConfigured
        }
        guard let baseURL = URL(string: baseURLString) else {
            throw BackendClientError.invalidEndpoint(baseURLString)
        }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let sessionToken {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    private func validate(httpResponse: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw BackendClientError.unauthorized
            }
            let payload = try? JSONDecoder.backendDecoder.decode(BackendErrorPayload.self, from: data)
            throw BackendClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: payload?.message ?? "Backend request failed."
            )
        }
    }

    private func appendMultipartField(
        name: String,
        value: String?,
        boundary: String,
        body: inout Data
    ) {
        guard let value else { return }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String,
        body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }
}

extension JSONEncoder {
    static var backendEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.backend.string(from: date))
        }
        return encoder
    }
}

extension JSONDecoder {
    static var backendDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.backend.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(string)"
            )
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    static let backend: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Data {
    var trimmingWhitespaceJSON: String {
        String(decoding: self, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TimeInterval {
    var millisecondsSince1970: Int {
        Int((self * 1000.0).rounded())
    }
}
