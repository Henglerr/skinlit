import Foundation
import UIKit

public enum OpenAIVisionSkinAnalyzerError: LocalizedError {
    case missingAPIKey
    case invalidImage
    case requestFailed(statusCode: Int, message: String)
    case incompleteResponse(reason: String?)
    case malformedResponse
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Add OPENAI_API_KEY in build settings."
        case .invalidImage:
            return "The selected image could not be prepared for analysis."
        case let .requestFailed(_, message):
            return "AI analysis failed: \(message)"
        case let .incompleteResponse(reason):
            if let reason, !reason.isEmpty {
                return "AI response was cut off (\(reason)). Please try again."
            }
            return "AI response was cut off. Please try again."
        case .malformedResponse:
            return "AI returned an unexpected response format."
        case .invalidPayload:
            return "AI returned invalid analysis data."
        }
    }
}

public struct OpenAIVisionSkinAnalyzer {
    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession

    public var isConfigured: Bool { !apiKey.isEmpty }

    public init(
        bundle: Bundle = .main,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
    ) {
        self.apiKey = (bundle.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.model = (bundle.object(forInfoDictionaryKey: "OpenAIVisionModel") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "gpt-4.1-mini"
        self.endpoint = endpoint
        self.session = session
    }

    public func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult {
        guard isConfigured else {
            throw OpenAIVisionSkinAnalyzerError.missingAPIKey
        }

        let preparedImageData = try prepareImageData(imageData)
        let base64Image = preparedImageData.base64EncodedString()
        let prompt = """
        You are a strict but FAIR cosmetic skin grader for ONE selfie (not medical advice).
        Penalize clearly visible issues, but do not under-score healthy skin.
        Avoid inflated scores and avoid unfairly low scores.

        Analyze ONLY skin in these regions:
        - Forehead (center + sides)
        - Left cheek and right cheek
        - Nose bridge/sides
        - Chin and jawline skin
        - Perioral skin (around mouth, not lips)
        - Under-eye skin (not eyelashes/eyeliner)

        Ignore completely:
        - Eyes, eyebrows, eyelashes, lips, teeth, nostril interior
        - Hair, beard/mustache, ears, neck, clothes, jewelry, hands
        - Background, lighting artifacts, camera borders, filters, makeup overlays

        Image quality gate (mandatory):
        - If face visibility is VERY weak (strong blur, strong shadow, heavy overexposure, major occlusion, face too small), cap every criterion at 3.0 and cap score at 3.0.
        - If visibility is very poor, use 0.0-2.0.
        - If visibility is acceptable, do NOT auto-cap; score normally.

        Criteria (0.0-10.0, one decimal):
        1) Hydration: dryness/dehydration vs balanced moisture/oil.
        2) Texture: roughness, visible pores, bumps, micro-texture irregularity.
        3) Uniformity: redness, blotchiness, uneven tone/pigmentation.
        4) Luminosity: healthy brightness/glow vs dullness.

        Severity mapping (use strictly):
        - 8.5-10.0: very healthy appearance, minimal visible issues.
        - 7.0-8.4: good skin, mild visible issues only.
        - 5.0-6.9: clear moderate issues in one or more criteria.
        - 3.0-4.9: pronounced issues, multiple visible concerns.
        - 0.0-2.9: severe issues or very poor visual quality.

        Hard scoring behavior:
        - If skin appears clear/even with only mild texture, overall should usually be 7.8-9.2.
        - Do NOT score clear healthy skin below 7.0 unless a clear issue is visible.
        - If forehead/cheeks/chin look clear, even and with low redness, overall should usually be >= 8.0.
        - If only minor imperfections are visible, keep criteria mostly in 7.8-9.0 (not 6.x).
        - If two or more criteria are moderate, overall score should usually be below 6.5.
        - If two or more criteria are pronounced, overall score should usually be below 5.0.
        - If severe inflammation/texture irregularity/uneven tone is obvious, allow 0.0-3.9.
        - When uncertain between two scores, choose the LOWER one.

        Calibration context (must influence scoring):
        - Reference GOOD selfie: clear/even skin, low redness, smooth texture, healthy glow.
          Expected criteria mostly 8.0-9.5 and overall usually 8.0-9.3.
        - Reference BAD selfie: severe visible acne/inflammation, rough texture, strong redness/uneven tone.
          Expected Texture/Uniformity often 1.0-4.0 and overall usually 1.5-4.8.
        - The score gap between clearly GOOD vs clearly BAD cases should be large (typically >= 3.0 points).
        - If photo resembles the BAD reference, do NOT output average/neutral scores.
        - If photo resembles the GOOD reference, do NOT keep score around 6-7 without clear visible issues.
        - Use the GOOD reference as baseline: if subject quality is similar, keep the score in GOOD range.

        Overall score rule:
        - score MUST be the arithmetic mean of the 4 criteria, rounded to one decimal.

        Output strict JSON only with EXACTLY these keys:
        {
          "score": number,
          "summary": "max 18 words, direct and concrete",
          "skin_type_detected": "short label like Oily · Combination",
          "criteria": {
            "Hydration": number,
            "Texture": number,
            "Uniformity": number,
            "Luminosity": number
          }
        }
        No markdown. No extra keys. No explanations.
        """

        let rawJSON = try await requestAnalysisJSON(prompt: prompt, base64Image: base64Image)
        let sanitizedJSON = sanitizeJSONCandidate(rawJSON)

        guard let rawData = sanitizedJSON.data(using: .utf8) else {
            throw OpenAIVisionSkinAnalyzerError.invalidPayload
        }

        let decoded = try JSONDecoder().decode(LLMAnalysisPayload.self, from: rawData)
        let normalizedCriteria = normalizeCriteria(decoded.criteria)
        let criteria = criticallyCalibrate(criteria: normalizedCriteria)
        let score = round1(criteria.values.reduce(0, +) / Double(criteria.count))

        return OnDeviceAnalysisResult(
            score: score,
            summary: decoded.summary.nonEmpty ?? "Analysis complete.",
            skinTypeDetected: decoded.skinTypeDetected.nonEmpty ?? "Unknown",
            criteria: criteria
        )
    }

    private func prepareImageData(_ imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw OpenAIVisionSkinAnalyzerError.invalidImage
        }

        let maxDimension: CGFloat = 1024
        let size = image.size
        let longestSide = max(size.width, size.height)

        let targetImage: UIImage
        if longestSide > maxDimension {
            let scale = maxDimension / longestSide
            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            targetImage = image
        }

        guard let jpegData = targetImage.jpegData(compressionQuality: 0.82) else {
            throw OpenAIVisionSkinAnalyzerError.invalidImage
        }
        return jpegData
    }

    private func requestAnalysisJSON(prompt: String, base64Image: String) async throws -> String {
        let lowerModel = model.lowercased()
        let isGPT5 = lowerModel.hasPrefix("gpt-5")
        let isNano = lowerModel.contains("nano")
        let compactPrompt = compactPromptTemplate()

        let attempts: [(prompt: String, maxOutputTokens: Int, reasoningEffort: String?)] = {
            if isNano {
                return [
                    (prompt, 700, "minimal"),
                    (compactPrompt, 1100, "minimal"),
                    (compactPrompt, 1600, nil)
                ]
            }
            if isGPT5 {
                return [
                    (prompt, 1400, "high"),
                    (prompt, 2200, "minimal"),
                    (compactPrompt, 1200, "minimal")
                ]
            }
            return [
                (prompt, 900, nil),
                (compactPrompt, 1300, nil)
            ]
        }()

        var lastRoot: [String: Any]?

        for (index, attempt) in attempts.enumerated() {
            let root = try await performRequest(
                prompt: attempt.prompt,
                base64Image: base64Image,
                maxOutputTokens: attempt.maxOutputTokens,
                reasoningEffort: attempt.reasoningEffort
            )
            lastRoot = root

            if let raw = extractOutputText(from: root), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return raw
            }

            let shouldRetry = index < attempts.count - 1
            if shouldRetry {
#if DEBUG
                if isTokenTruncation(root: root) {
                    print("OpenAI response truncated at \(attempt.maxOutputTokens) output tokens. Retrying with adjusted request.")
                } else {
                    print("OpenAI response returned no parseable output text. Retrying with adjusted request.")
                }
#endif
                continue
            }

            if let reason = incompleteReason(from: root) {
                throw OpenAIVisionSkinAnalyzerError.incompleteResponse(reason: reason)
            }
            throw OpenAIVisionSkinAnalyzerError.malformedResponse
        }

        if let reason = lastRoot.flatMap(incompleteReason(from:)) {
            throw OpenAIVisionSkinAnalyzerError.incompleteResponse(reason: reason)
        }
        throw OpenAIVisionSkinAnalyzerError.malformedResponse
    }

    private func performRequest(
        prompt: String,
        base64Image: String,
        maxOutputTokens: Int,
        reasoningEffort: String?
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ],
                        [
                            "type": "input_image",
                            "image_url": "data:image/jpeg;base64,\(base64Image)",
                            "detail": "high"
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": maxOutputTokens
        ]

        if let reasoningEffort, !reasoningEffort.isEmpty {
            payload["reasoning"] = ["effort": reasoningEffort]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIVisionSkinAnalyzerError.malformedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = responseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAIVisionSkinAnalyzerError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIVisionSkinAnalyzerError.malformedResponse
        }

        return root
    }

    private func compactPromptTemplate() -> String {
        """
        Strict but fair cosmetic skin scoring from one selfie (not medical advice).
        Analyze only visible facial skin: forehead, cheeks, nose, chin/jawline, perioral, under-eye skin.
        Ignore eyes/lips/hair/background/accessories.
        Use 0.0-10.0 (one decimal) for Hydration, Texture, Uniformity, Luminosity.
        Be critical on visible acne/redness/roughness, but do not under-score healthy skin.
        If skin is clear/even with only minor imperfections, overall should usually be >= 8.0.
        If image quality is very weak, cap each criterion and overall score at 3.0.
        score must be mean(criteria) rounded to one decimal.
        Return strict JSON only:
        {"score":number,"summary":"max 18 words","skin_type_detected":"short label","criteria":{"Hydration":number,"Texture":number,"Uniformity":number,"Luminosity":number}}
        No markdown, no extra keys.
        """
    }

    private func extractOutputText(from root: [String: Any]) -> String? {
        if let outputText = root["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        guard let outputItems = root["output"] as? [[String: Any]] else {
            return nil
        }

        for item in outputItems where (item["type"] as? String) == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if let text = block["text"] as? String, !text.isEmpty {
                    return text
                }

                if let textObject = block["text"] as? [String: Any],
                   let text = textObject["value"] as? String,
                   !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    private func isTokenTruncation(root: [String: Any]) -> Bool {
        guard (root["status"] as? String) == "incomplete" else { return false }
        if let details = root["incomplete_details"] as? [String: Any],
           let reason = details["reason"] as? String {
            return reason == "max_output_tokens"
        }
        return true
    }

    private func incompleteReason(from root: [String: Any]) -> String? {
        guard (root["status"] as? String) == "incomplete" else { return nil }
        if let details = root["incomplete_details"] as? [String: Any],
           let reason = details["reason"] as? String,
           !reason.isEmpty {
            return reason
        }
        return "incomplete"
    }

    private func sanitizeJSONCandidate(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }

        return text
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

    private func criticallyCalibrate(criteria: [String: Double]) -> [String: Double] {
        let canonicalNames = ["Hydration", "Texture", "Uniformity", "Luminosity"]
        var firstPass: [String: Double] = [:]

        for name in canonicalNames {
            let raw = clamp(criteria[name] ?? 0, min: 0, max: 10)
            // Expand contrast around 6.0 so good and bad skin separate more clearly.
            var adjusted = 6.0 + (raw - 6.0) * 1.10

            // Penalize weak criteria while keeping healthy skin from being dragged down.
            if adjusted < 6.0 { adjusted -= 0.12 }
            if adjusted < 5.0 { adjusted -= 0.20 }
            if adjusted < 4.0 { adjusted -= 0.30 }

            // Reward clearly strong criteria to better separate good skin.
            if adjusted > 7.5 { adjusted += 0.18 }
            if adjusted > 8.4 { adjusted += 0.22 }
            if adjusted > 9.1 { adjusted += 0.12 }

            firstPass[name] = round1(clamp(adjusted, min: 0, max: 10))
        }

        let values = Array(firstPass.values)
        let weakCount = values.filter { $0 < 6.0 }.count
        let severeCount = values.filter { $0 < 4.5 }.count
        let strongCount = values.filter { $0 >= 7.8 }.count
        let eliteCount = values.filter { $0 >= 8.8 }.count
        let average = values.reduce(0, +) / Double(values.count)
        let minimum = values.min() ?? 0

        var groupShift = 0.0
        if weakCount >= 2 { groupShift -= 0.18 }
        if weakCount >= 3 { groupShift -= 0.24 }
        if severeCount >= 1 { groupShift -= 0.22 }
        if severeCount >= 2 { groupShift -= 0.30 }
        if strongCount >= 3 && weakCount == 0 { groupShift += 0.30 }
        if eliteCount >= 2 && weakCount == 0 { groupShift += 0.22 }
        if minimum >= 7.0 && average >= 7.6 { groupShift += 0.18 }
        if average >= 8.3 && weakCount == 0 { groupShift += 0.15 }
        if minimum >= 6.8 && average >= 7.5 { groupShift += 0.25 }
        if minimum >= 7.2 && average >= 7.9 { groupShift += 0.25 }

        guard groupShift != 0 else { return firstPass }

        var final: [String: Double] = [:]
        for name in canonicalNames {
            let value = firstPass[name] ?? 0
            final[name] = round1(clamp(value + groupShift, min: 0, max: 10))
        }
        return final
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

private struct LLMAnalysisPayload: Decodable {
    let score: Double
    let summary: String
    let skinTypeDetected: String
    let criteria: [String: Double]

    enum CodingKeys: String, CodingKey {
        case score
        case summary
        case skinTypeDetected = "skin_type_detected"
        case criteria
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
