import Foundation
import UIKit

public enum SkinAnalysisRemoteError: LocalizedError {
    case missingEndpoint
    case invalidImage
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Cloud analysis endpoint is not configured."
        case .invalidImage:
            return "The selected image could not be prepared for analysis."
        case let .requestFailed(_, message):
            return "Cloud analysis failed: \(message)"
        case .malformedResponse:
            return "Cloud analysis returned an unexpected response format."
        case .invalidPayload:
            return "Cloud analysis returned invalid data."
        }
    }
}

public struct BackendSkinAnalysisClient: SkinAnalysisRemoteClient {
    private let endpointString: String
    private let authToken: String
    private let session: URLSession

    public var isConfigured: Bool {
        let trimmed = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("$(") else { return false }
        return URL(string: trimmed) != nil
    }

    public init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.endpointString = AppConfig.skinAnalysisAPIEndpoint(bundle: bundle)
        self.authToken = AppConfig.skinAnalysisAPIAuthToken(bundle: bundle)
        self.session = session
    }

    public func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult {
        guard isConfigured, let endpoint = URL(string: endpointString) else {
            throw SkinAnalysisRemoteError.missingEndpoint
        }

        let preparedImageData = try prepareImageData(imageData)
        let payload = BackendAnalysisRequest(
            imageBase64: preparedImageData.base64EncodedString(),
            mimeType: "image/jpeg",
            source: "ios"
        )

        let bodyData = try JSONEncoder().encode(payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkinAnalysisRemoteError.malformedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = responseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw SkinAnalysisRemoteError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try decodePayload(from: data)
        let normalizedCriteria = normalizeCriteria(decoded.criteria)
        let normalizedScore = normalizeScore(decoded.score, criteria: normalizedCriteria)

        return OnDeviceAnalysisResult(
            score: normalizedScore,
            summary: decoded.summary.nonEmpty ?? "Analysis complete.",
            skinTypeDetected: decoded.skinTypeDetected.nonEmpty ?? "Unknown",
            criteria: normalizedCriteria
        )
    }

    private func prepareImageData(_ imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw SkinAnalysisRemoteError.invalidImage
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
            throw SkinAnalysisRemoteError.invalidImage
        }

        return jpegData
    }

    private func decodePayload(from data: Data) throws -> BackendAnalysisPayload {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(BackendAnalysisPayload.self, from: data) {
            return direct
        }

        if let envelope = try? decoder.decode(BackendAnalysisEnvelope.self, from: data) {
            return envelope.analysis
        }

        throw SkinAnalysisRemoteError.invalidPayload
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

    private func normalizeScore(_ rawScore: Double, criteria: [String: Double]) -> Double {
        let clamped = clamp(rawScore, min: 0, max: 10)
        if clamped > 0 {
            return round1(clamped)
        }

        let average = criteria.values.reduce(0, +) / Double(criteria.count)
        return round1(clamp(average, min: 0, max: 10))
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

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

public typealias OpenAIVisionSkinAnalyzer = BackendSkinAnalysisClient

private struct BackendAnalysisRequest: Encodable {
    let imageBase64: String
    let mimeType: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case source
    }
}

private struct BackendAnalysisEnvelope: Decodable {
    let analysis: BackendAnalysisPayload
}

private struct BackendAnalysisPayload: Decodable {
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
