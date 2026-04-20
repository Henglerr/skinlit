import Foundation

public enum SkinAnalysisRemoteError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case referenceCatalogIncomplete(missingIDs: [String])
    case invalidImage
    case insufficientImageQuality(reasons: [SkinImageQualityReason])
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse
    case invalidPayload
    case contextVerificationFailed(expectedVersion: String, receivedVersion: String?)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Add your API key before running scans."
        case let .invalidEndpoint(endpoint):
            return "The analysis endpoint is invalid: \(endpoint)"
        case let .referenceCatalogIncomplete(missingIDs):
            let preview = missingIDs.prefix(4).joined(separator: ", ")
            return "Reference catalog is incomplete. Missing: \(preview). Add all 25 reference images before scanning."
        case .invalidImage:
            return "The selected image could not be prepared for analysis."
        case let .insufficientImageQuality(reasons):
            let details = reasons.map(\.userFacingDescription).joined(separator: ", ")
            return "Photo quality is not good enough for a reliable skin score. Issues: \(details)."
        case let .requestFailed(_, message):
            return "OpenAI analysis failed: \(message)"
        case .malformedResponse:
            return "OpenAI returned an unexpected response format."
        case .invalidPayload:
            return "OpenAI returned invalid analysis data."
        case let .contextVerificationFailed(expectedVersion, receivedVersion):
            if let receivedVersion, !receivedVersion.isEmpty {
                return "Analysis used the wrong prompt version. Expected \(expectedVersion), got \(receivedVersion)."
            }
            return "Analysis did not confirm the expected prompt version \(expectedVersion)."
        }
    }
}

public struct OpenAIResponsesSkinAnalyzer: SkinAnalysisRemoteClient {
    private let endpointString: String
    private let authToken: String
    private let model: String
    private let reasoningEffort: String
    private let session: URLSession
    private let analysisVersion: String
    private let referenceCatalogLoader: () throws -> SkinReferenceCatalog

    public var isConfigured: Bool {
        let trimmed = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }

    public init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.endpointString = AppConfig.skinAnalysisAPIEndpoint(bundle: bundle)
        self.authToken = AppConfig.openAIAPIKey(bundle: bundle)
        self.model = AppConfig.openAIVisionModel(bundle: bundle)
        self.reasoningEffort = AppConfig.openAIVisionReasoningEffort(bundle: bundle)
        self.session = session
        self.analysisVersion = AppConfig.skinAnalysisVersion
        self.referenceCatalogLoader = { try SkinReferenceCatalog(bundle: bundle) }
    }

    init(
        endpointString: String = "",
        authToken: String = "",
        model: String = AppConfig.defaultOpenAIVisionModel,
        reasoningEffort: String = AppConfig.defaultOpenAIVisionReasoningEffort,
        session: URLSession = .shared,
        analysisVersion: String = AppConfig.skinAnalysisVersion,
        referenceCatalogLoader: @escaping () throws -> SkinReferenceCatalog
    ) {
        self.endpointString = endpointString
        self.authToken = authToken
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.session = session
        self.analysisVersion = analysisVersion
        self.referenceCatalogLoader = referenceCatalogLoader
    }

    public func analyze(imageData: Data, userContext: SkinAnalysisUserContext?) async throws -> OnDeviceAnalysisResult {
        try await analyze(
            imageData: imageData,
            userContext: userContext,
            ignoredQualityReasons: []
        )
    }

    public func analyze(
        imageData: Data,
        userContext: SkinAnalysisUserContext?,
        ignoredQualityReasons: Set<SkinImageQualityReason>
    ) async throws -> OnDeviceAnalysisResult {
        guard isConfigured else {
            throw SkinAnalysisRemoteError.missingAPIKey
        }

        let endpoint = try resolveEndpoint()
        let referenceCatalog = try referenceCatalogLoader()
        try referenceCatalog.validateRequiredAssets()

        let normalizedImageData: Data
        do {
            normalizedImageData = try FaceImageProcessor.normalizedVariant(from: imageData)
        } catch {
            throw SkinAnalysisRemoteError.invalidImage
        }

        let classifierReferences = try referenceCatalog.assets(for: AppConfig.centerReferenceIDs)
        let classification = try await classifyBand(
            endpoint: endpoint,
            rawImageData: imageData,
            normalizedImageData: normalizedImageData,
            references: classifierReferences,
            userContext: userContext
        )
        try verifyAnalysisVersion(classification.analysisVersion)

        if classification.imageQualityStatus == .insufficient {
            let blockingReasons = classification.imageQualityReasons.filter { !ignoredQualityReasons.contains($0) }
            if !blockingReasons.isEmpty {
                throw SkinAnalysisRemoteError.insufficientImageQuality(reasons: blockingReasons)
            }
        }

        let detailedReferences = try referenceCatalog.assets(
            for: AppConfig.detailedReferenceIDs(for: classification.predictedBand)
        )
        let detailed = try await requestDetailedAssessment(
            endpoint: endpoint,
            rawImageData: imageData,
            normalizedImageData: normalizedImageData,
            predictedBand: classification.predictedBand,
            references: detailedReferences,
            userContext: userContext
        )
        try verifyAnalysisVersion(detailed.analysisVersion)

        let normalizedCriteria = normalizeCriteria(detailed.criteria)
        let score = SkinScoreComputation.finalScore(
            criteria: normalizedCriteria,
            observedConditions: detailed.observedConditions
        )

        return OnDeviceAnalysisResult(
            score: score,
            summary: normalizedSummary(detailed.summary),
            skinTypeDetected: detailed.skinTypeDetected.nonEmpty ?? "Unknown",
            criteria: normalizedCriteria,
            criterionInsights: detailed.criterionInsights
        )
    }

    private func classifyBand(
        endpoint: URL,
        rawImageData: Data,
        normalizedImageData: Data,
        references: [SkinReferenceAsset],
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinBandClassifierResponse {
        let responseText = try await performStructuredRequest(
            endpoint: endpoint,
            schemaName: "skin_band_classifier",
            schema: classificationSchema(),
            developerPrompt: AppConfig.classificationPrompt(userContext: userContext),
            supportingText: classificationSupportingText(references: references),
            imageItems: makeImageItems(
                rawImageData: rawImageData,
                normalizedImageData: normalizedImageData,
                references: references
            ),
            maxOutputTokens: 400
        )

        return try decodeResponseText(responseText, as: SkinBandClassifierResponse.self)
    }

    private func requestDetailedAssessment(
        endpoint: URL,
        rawImageData: Data,
        normalizedImageData: Data,
        predictedBand: String,
        references: [SkinReferenceAsset],
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinDetailedAssessmentResponse {
        let responseText = try await performStructuredRequest(
            endpoint: endpoint,
            schemaName: "skin_detailed_assessment",
            schema: detailedAssessmentSchema(),
            developerPrompt: AppConfig.detailedAssessmentPrompt(userContext: userContext),
            supportingText: detailedSupportingText(
                predictedBand: predictedBand,
                references: references
            ),
            imageItems: makeImageItems(
                rawImageData: rawImageData,
                normalizedImageData: normalizedImageData,
                references: references
            ),
            maxOutputTokens: 700
        )

        return try decodeResponseText(responseText, as: SkinDetailedAssessmentResponse.self)
    }

    private func performStructuredRequest(
        endpoint: URL,
        schemaName: String,
        schema: [String: Any],
        developerPrompt: String,
        supportingText: String,
        imageItems: [[String: Any]],
        maxOutputTokens: Int
    ) async throws -> String {
        let developerMessage: [String: Any] = [
            "role": "developer",
            "content": [
                [
                    "type": "input_text",
                    "text": developerPrompt
                ]
            ]
        ]

        var userContent: [[String: Any]] = [
            [
                "type": "input_text",
                "text": supportingText
            ]
        ]
        userContent.append(contentsOf: imageItems)

        let userMessage: [String: Any] = [
            "role": "user",
            "content": userContent
        ]

        var body: [String: Any] = [
            "model": model,
            "input": [developerMessage, userMessage],
            "max_output_tokens": maxOutputTokens,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        let trimmedReasoningEffort = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReasoningEffort.isEmpty {
            body["reasoning"] = [
                "effort": trimmedReasoningEffort
            ]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkinAnalysisRemoteError.malformedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = responseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw SkinAnalysisRemoteError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return try extractOutputText(from: data)
    }

    private func makeImageItems(
        rawImageData: Data,
        normalizedImageData: Data,
        references: [SkinReferenceAsset]
    ) -> [[String: Any]] {
        var items: [[String: Any]] = [
            imageItem(imageData: rawImageData, mimeType: "image/jpeg"),
            imageItem(imageData: normalizedImageData, mimeType: "image/jpeg")
        ]

        items.append(contentsOf: references.map { reference in
            imageItem(imageData: reference.imageData, mimeType: reference.mimeType)
        })
        return items
    }

    private func imageItem(imageData: Data, mimeType: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": "data:\(mimeType);base64,\(imageData.base64EncodedString())",
            "detail": "high"
        ]
    }

    private func classificationSupportingText(references: [SkinReferenceAsset]) -> String {
        let referenceLines = references.enumerated().map { index, reference in
            "\(index + 3). \(reference.anchor.id) | band \(reference.bandLabel) | suggested \(reference.anchor.suggestedScore) | \(reference.anchor.description)"
        }.joined(separator: "\n")

        return """
Image order:
1. User selfie raw face crop.
2. User selfie normalized face crop for exposure balancing only.
\(referenceLines)

Use the attached reference images as band anchors. Return JSON only.
"""
    }

    private func detailedSupportingText(
        predictedBand: String,
        references: [SkinReferenceAsset]
    ) -> String {
        let referenceLines = references.enumerated().map { index, reference in
            "\(index + 3). \(reference.anchor.id) | band \(reference.bandLabel) | suggested \(reference.anchor.suggestedScore) | \(reference.anchor.description)"
        }.joined(separator: "\n")

        return """
The coarse classifier placed this selfie closest to band \(predictedBand).

Image order:
1. User selfie raw face crop.
2. User selfie normalized face crop for exposure balancing only.
\(referenceLines)

Use these anchors to grade the four criteria and objective conditions.
Do not return an overall score.
Return JSON only.
"""
    }

    private func classificationSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "analysis_version",
                "image_quality_status",
                "image_quality_reasons",
                "predicted_band",
                "observed_conditions"
            ],
            "properties": [
                "analysis_version": [
                    "type": "string",
                    "enum": [analysisVersion]
                ],
                "image_quality_status": [
                    "type": "string",
                    "enum": ["ok", "insufficient"]
                ],
                "image_quality_reasons": [
                    "type": "array",
                    "items": [
                        "type": "string",
                        "enum": AppConfig.imageQualityReasonValues
                    ]
                ],
                "predicted_band": [
                    "type": "string",
                    "enum": ["0-2", "2-4", "4-6", "6-8", "8-10"]
                ],
                "observed_conditions": observedConditionsSchema()
            ]
        ]
    }

    private func detailedAssessmentSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "analysis_version",
                "summary",
                "skin_type_detected",
                "criteria",
                "criterion_insights",
                "observed_conditions"
            ],
            "properties": [
                "analysis_version": [
                    "type": "string",
                    "enum": [analysisVersion]
                ],
                "summary": [
                    "type": "string"
                ],
                "skin_type_detected": [
                    "type": "string"
                ],
                "criteria": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["Hydration", "Texture", "Uniformity", "Luminosity"],
                    "properties": [
                        "Hydration": numericCriterionSchema(),
                        "Texture": numericCriterionSchema(),
                        "Uniformity": numericCriterionSchema(),
                        "Luminosity": numericCriterionSchema()
                    ]
                ],
                "criterion_insights": criterionInsightsSchema(),
                "observed_conditions": observedConditionsSchema()
            ]
        ]
    }

    private func criterionInsightsSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["Hydration", "Texture", "Uniformity", "Luminosity"],
            "properties": [
                "Hydration": criterionInsightSchema(),
                "Texture": criterionInsightSchema(),
                "Uniformity": criterionInsightSchema(),
                "Luminosity": criterionInsightSchema()
            ]
        ]
    }

    private func criterionInsightSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "status",
                "summary",
                "positive_observations",
                "negative_observations",
                "routine_focus"
            ],
            "properties": [
                "status": ["type": "string"],
                "summary": ["type": "string"],
                "positive_observations": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "negative_observations": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "routine_focus": ["type": "string"]
            ]
        ]
    }

    private func observedConditionsSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "active_inflammation",
                "scarring_pitting",
                "texture_irregularity",
                "redness_irritation",
                "dryness_flaking"
            ],
            "properties": [
                "active_inflammation": severitySchema(),
                "scarring_pitting": severitySchema(),
                "texture_irregularity": severitySchema(),
                "redness_irritation": severitySchema(),
                "dryness_flaking": severitySchema()
            ]
        ]
    }

    private func severitySchema() -> [String: Any] {
        [
            "type": "string",
            "enum": AppConfig.severityValues
        ]
    }

    private func numericCriterionSchema() -> [String: Any] {
        [
            "type": "number",
            "minimum": 0,
            "maximum": 10
        ]
    }

    private func decodeResponseText<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw SkinAnalysisRemoteError.invalidPayload
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkinAnalysisRemoteError.malformedResponse
        }

        if let outputText = root["output_text"] as? String, let nonEmpty = outputText.nonEmpty {
            return nonEmpty
        }

        if let output = root["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String, let nonEmpty = text.nonEmpty {
                        return nonEmpty
                    }
                }
            }
        }

        throw SkinAnalysisRemoteError.malformedResponse
    }

    private func responseErrorMessage(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }

        return message
    }

    private func verifyAnalysisVersion(_ receivedVersion: String) throws {
        guard receivedVersion == analysisVersion else {
            throw SkinAnalysisRemoteError.contextVerificationFailed(
                expectedVersion: analysisVersion,
                receivedVersion: receivedVersion.nonEmpty
            )
        }
    }

    private func normalizeCriteria(_ rawCriteria: [String: Double]) -> [String: Double] {
        let canonicalNames = ["Hydration", "Texture", "Uniformity", "Luminosity"]
        var normalized: [String: Double] = [:]

        for name in canonicalNames {
            if let exact = rawCriteria[name] {
                normalized[name] = round1(clamp(exact, min: 0, max: 10))
                continue
            }

            if let matched = rawCriteria.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
                normalized[name] = round1(clamp(matched.value, min: 0, max: 10))
            }
        }

        for name in canonicalNames where normalized[name] == nil {
            normalized[name] = 0
        }

        return normalized
    }

    private func normalizedSummary(_ rawSummary: String) -> String {
        let trimmed = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Analysis complete." }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count <= 90 {
            return trimmed
        }
        return words.prefix(90).joined(separator: " ")
    }

    private func resolveEndpoint() throws -> URL {
        let trimmed = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") {
            return AppConfig.defaultOpenAIResponsesURL
        }

        guard let url = URL(string: trimmed) else {
            throw SkinAnalysisRemoteError.invalidEndpoint(trimmed)
        }
        return url
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

public typealias BackendSkinAnalysisClient = OpenAIResponsesSkinAnalyzer
public typealias OpenAIVisionSkinAnalyzer = OpenAIResponsesSkinAnalyzer

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
