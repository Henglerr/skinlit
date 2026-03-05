import Foundation

public struct BackendSession: Codable, Equatable {
    public let sessionToken: String
    public let userID: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
        case userID = "user_id"
        case expiresAt = "expires_at"
    }
}

public enum RemoteScanJobStatus: String, Codable {
    case queued
    case running
    case succeeded
    case failed
    case rejected
}

public struct RemoteScanJob: Codable, Equatable {
    public let jobID: String
    public let status: RemoteScanJobStatus
    public let failureCode: String?
    public let failureMessage: String?
    public let scanID: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case failureCode = "failure_code"
        case failureMessage = "failure_message"
        case scanID = "scan_id"
    }
}

public struct RemoteScanResult: Codable, Equatable {
    public let id: String
    public let score: Double
    public let summary: String
    public let skinTypeDetected: String
    public let criteria: [String: Double]
    public let observedConditions: SkinObservedConditions
    public let predictedBand: String
    public let imageQualityStatus: SkinImageQualityStatus
    public let imageQualityReasons: [SkinImageQualityReason]
    public let analysisVersion: String
    public let referenceCatalogVersion: String
    public let model: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case score
        case summary
        case skinTypeDetected = "skin_type_detected"
        case criteria
        case observedConditions = "observed_conditions"
        case predictedBand = "predicted_band"
        case imageQualityStatus = "image_quality_status"
        case imageQualityReasons = "image_quality_reasons"
        case analysisVersion = "analysis_version"
        case referenceCatalogVersion = "reference_catalog_version"
        case model
        case createdAt = "created_at"
    }

    public var asAnalysisResult: OnDeviceAnalysisResult {
        OnDeviceAnalysisResult(
            score: score,
            summary: summary,
            skinTypeDetected: skinTypeDetected,
            criteria: criteria
        )
    }
}

public struct RemoteOnboardingProfile: Codable, Equatable {
    public let skinTypes: [String]
    public let goal: String
    public let routineLevel: String
    public let completedAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case skinTypes = "skin_types"
        case goal
        case routineLevel = "routine_level"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteJourneyLog: Codable, Equatable {
    public let dayKey: String
    public let dayStartAt: Date
    public let routineStepIDs: [String]
    public let treatmentIDs: [String]
    public let skinStatusIDs: [String]
    public let note: String
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case dayKey = "day_key"
        case dayStartAt = "day_start_at"
        case routineStepIDs = "routine_step_ids"
        case treatmentIDs = "treatment_ids"
        case skinStatusIDs = "skin_status_ids"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct SkinAnalysisOutcome: Equatable {
    public let analysisID: String
    public let result: OnDeviceAnalysisResult
}

public enum BackendClientError: LocalizedError, Equatable {
    case backendNotConfigured
    case missingSession
    case missingProviderToken
    case invalidEndpoint(String)
    case invalidResponse
    case unauthorized
    case jobTimedOut
    case scanRejected(message: String)
    case requestFailed(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "Backend URL is not configured."
        case .missingSession:
            return "No backend session is available."
        case .missingProviderToken:
            return "Could not obtain the provider identity token."
        case let .invalidEndpoint(endpoint):
            return "The backend endpoint is invalid: \(endpoint)"
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .unauthorized:
            return "Your backend session is no longer valid. Sign in again."
        case .jobTimedOut:
            return "Analysis took too long. Please try again."
        case let .scanRejected(message):
            return message
        case let .requestFailed(_, message):
            return message
        }
    }
}

struct BackendErrorPayload: Decodable {
    let error: String?
    let message: String?
}

public struct RemoteScanImportItem: Encodable {
    let clientScanId: String
    let score: Double
    let summary: String
    let skinTypeDetected: String
    let criteria: [String: Double]
    let observedConditions: SkinObservedConditions
    let predictedBand: String
    let imageQualityStatus: SkinImageQualityStatus
    let imageQualityReasons: [SkinImageQualityReason]
    let analysisVersion: String
    let referenceCatalogVersion: String
    let model: String
    let inputImageHash: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case clientScanId = "clientScanId"
        case score
        case summary
        case skinTypeDetected
        case criteria
        case observedConditions
        case predictedBand
        case imageQualityStatus
        case imageQualityReasons
        case analysisVersion
        case referenceCatalogVersion
        case model
        case inputImageHash
        case createdAt
    }
}

public struct RemoteJourneyImportItem: Encodable {
    let dayKey: String
    let dayStartAt: String
    let routineStepIDs: [String]
    let treatmentIDs: [String]
    let skinStatusIDs: [String]
    let note: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case dayKey
        case dayStartAt
        case routineStepIDs
        case treatmentIDs
        case skinStatusIDs
        case note
        case createdAt
        case updatedAt
    }
}
