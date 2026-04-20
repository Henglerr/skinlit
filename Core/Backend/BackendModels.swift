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

public struct RemoteCreateScanJobResponse: Codable, Equatable {
    public let jobID: String
    public let status: RemoteScanJobStatus

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
    }
}

public enum AnalysisDebugSource: String, Codable, Equatable {
    case remoteFresh = "remote_fresh"
    case backendReuse = "backend_reuse"
    case remoteSynced = "remote_synced"
    case localCache = "local_cache"
    case qualityOverride = "quality_override"
    case unknown

    public var userFacingLabel: String {
        switch self {
        case .remoteFresh:
            return "remote"
        case .backendReuse:
            return "backend reuse"
        case .remoteSynced:
            return "remote sync"
        case .localCache:
            return "local cache"
        case .qualityOverride:
            return "quality override"
        case .unknown:
            return "unknown"
        }
    }
}

public enum ReferenceVerificationVerdict: String, Codable, Equatable {
    case confirm
    case adjustUp = "adjust_up"
    case adjustDown = "adjust_down"

    public var userFacingLabel: String {
        switch self {
        case .confirm:
            return "confirmed"
        case .adjustUp:
            return "adjusted up"
        case .adjustDown:
            return "adjusted down"
        }
    }
}

public struct LocalAnalysisDebugMetadata: Codable, Equatable {
    public let analysisVersion: String?
    public let predictedBand: String?
    public let observedConditions: SkinObservedConditions?
    public let imageQualityStatus: SkinImageQualityStatus?
    public let imageQualityReasons: [SkinImageQualityReason]
    public let referenceCatalogVersion: String?
    public let baseScore: Double?
    public let finalScore: Double?
    public let adjustmentDelta: Double?
    public let matchedReferenceIDs: [String]?
    public let verificationVerdict: ReferenceVerificationVerdict?
    public let adjustmentReason: String?
    public let localStabilityAdjustmentApplied: Bool?
    public let localStabilityReferenceScore: Double?
    public let localStabilityNeighborCount: Int?
    public let qualityOverrideAccepted: Bool?
    public let qualityOverrideAcceptedReasons: [SkinImageQualityReason]?
    public let qualityOverrideLabel: String?
    public let model: String?
    public let source: AnalysisDebugSource

    public init(
        analysisVersion: String?,
        predictedBand: String?,
        observedConditions: SkinObservedConditions?,
        imageQualityStatus: SkinImageQualityStatus?,
        imageQualityReasons: [SkinImageQualityReason],
        referenceCatalogVersion: String?,
        baseScore: Double? = nil,
        finalScore: Double? = nil,
        adjustmentDelta: Double? = nil,
        matchedReferenceIDs: [String]? = nil,
        verificationVerdict: ReferenceVerificationVerdict? = nil,
        adjustmentReason: String? = nil,
        localStabilityAdjustmentApplied: Bool? = nil,
        localStabilityReferenceScore: Double? = nil,
        localStabilityNeighborCount: Int? = nil,
        qualityOverrideAccepted: Bool? = nil,
        qualityOverrideAcceptedReasons: [SkinImageQualityReason]? = nil,
        qualityOverrideLabel: String? = nil,
        model: String?,
        source: AnalysisDebugSource
    ) {
        self.analysisVersion = analysisVersion
        self.predictedBand = predictedBand
        self.observedConditions = observedConditions
        self.imageQualityStatus = imageQualityStatus
        self.imageQualityReasons = imageQualityReasons
        self.referenceCatalogVersion = referenceCatalogVersion
        self.baseScore = baseScore
        self.finalScore = finalScore
        self.adjustmentDelta = adjustmentDelta
        self.matchedReferenceIDs = matchedReferenceIDs
        self.verificationVerdict = verificationVerdict
        self.adjustmentReason = adjustmentReason
        self.localStabilityAdjustmentApplied = localStabilityAdjustmentApplied
        self.localStabilityReferenceScore = localStabilityReferenceScore
        self.localStabilityNeighborCount = localStabilityNeighborCount
        self.qualityOverrideAccepted = qualityOverrideAccepted
        self.qualityOverrideAcceptedReasons = qualityOverrideAcceptedReasons
        self.qualityOverrideLabel = qualityOverrideLabel
        self.model = model
        self.source = source
    }

    public func with(source: AnalysisDebugSource) -> LocalAnalysisDebugMetadata {
        LocalAnalysisDebugMetadata(
            analysisVersion: analysisVersion,
            predictedBand: predictedBand,
            observedConditions: observedConditions,
            imageQualityStatus: imageQualityStatus,
            imageQualityReasons: imageQualityReasons,
            referenceCatalogVersion: referenceCatalogVersion,
            baseScore: baseScore,
            finalScore: finalScore,
            adjustmentDelta: adjustmentDelta,
            matchedReferenceIDs: matchedReferenceIDs,
            verificationVerdict: verificationVerdict,
            adjustmentReason: adjustmentReason,
            localStabilityAdjustmentApplied: localStabilityAdjustmentApplied,
            localStabilityReferenceScore: localStabilityReferenceScore,
            localStabilityNeighborCount: localStabilityNeighborCount,
            qualityOverrideAccepted: qualityOverrideAccepted,
            qualityOverrideAcceptedReasons: qualityOverrideAcceptedReasons,
            qualityOverrideLabel: qualityOverrideLabel,
            model: model,
            source: source
        )
    }
}

public struct RemoteScanResult: Codable, Equatable {
    public let id: String
    public let score: Double
    public let summary: String
    public let skinTypeDetected: String
    public let criteria: [String: Double]
    public let criterionInsights: [String: SkinCriterionInsight]?
    public let observedConditions: SkinObservedConditions
    public let predictedBand: String
    public let imageQualityStatus: SkinImageQualityStatus
    public let imageQualityReasons: [SkinImageQualityReason]
    public let analysisVersion: String
    public let referenceCatalogVersion: String
    public let baseScore: Double?
    public let verifiedScore: Double?
    public let adjustmentDelta: Double?
    public let matchedReferenceIDs: [String]?
    public let verificationVerdict: ReferenceVerificationVerdict?
    public let adjustmentReason: String?
    public let model: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case score
        case summary
        case skinTypeDetected = "skin_type_detected"
        case criteria
        case criterionInsights = "criterion_insights"
        case observedConditions = "observed_conditions"
        case predictedBand = "predicted_band"
        case imageQualityStatus = "image_quality_status"
        case imageQualityReasons = "image_quality_reasons"
        case analysisVersion = "analysis_version"
        case referenceCatalogVersion = "reference_catalog_version"
        case baseScore = "base_score"
        case verifiedScore = "verified_score"
        case adjustmentDelta = "adjustment_delta"
        case matchedReferenceIDs = "matched_reference_ids"
        case verificationVerdict = "verification_verdict"
        case adjustmentReason = "adjustment_reason"
        case model
        case createdAt = "created_at"
    }

    public var asAnalysisResult: OnDeviceAnalysisResult {
        OnDeviceAnalysisResult(
            score: score,
            summary: summary,
            skinTypeDetected: skinTypeDetected,
            criteria: criteria,
            criterionInsights: criterionInsights
        )
    }

    public func debugMetadata(source: AnalysisDebugSource) -> LocalAnalysisDebugMetadata {
        LocalAnalysisDebugMetadata(
            analysisVersion: analysisVersion,
            predictedBand: predictedBand,
            observedConditions: observedConditions,
            imageQualityStatus: imageQualityStatus,
            imageQualityReasons: imageQualityReasons,
            referenceCatalogVersion: referenceCatalogVersion,
            baseScore: baseScore,
            finalScore: verifiedScore ?? score,
            adjustmentDelta: adjustmentDelta ?? baseScore.map { score - $0 },
            matchedReferenceIDs: matchedReferenceIDs,
            verificationVerdict: verificationVerdict,
            adjustmentReason: adjustmentReason,
            model: model,
            source: source
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

public struct RemoteReferralStatus: Codable, Equatable {
    public let inviteCode: String?
    public let inviteURLString: String?
    public let claimedCode: String?
    public let validatedReferralCount: Int
    public let pendingReferralCount: Int
    public let rewardCount: Int
    public let updatedAt: Date?

    public init(
        inviteCode: String?,
        inviteURLString: String?,
        claimedCode: String?,
        validatedReferralCount: Int,
        pendingReferralCount: Int,
        rewardCount: Int,
        updatedAt: Date?
    ) {
        self.inviteCode = inviteCode
        self.inviteURLString = inviteURLString
        self.claimedCode = claimedCode
        self.validatedReferralCount = validatedReferralCount
        self.pendingReferralCount = pendingReferralCount
        self.rewardCount = rewardCount
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case inviteURLString = "invite_url"
        case claimedCode = "claimed_code"
        case validatedReferralCount = "validated_referral_count"
        case pendingReferralCount = "pending_referral_count"
        case rewardCount = "reward_count"
        case updatedAt = "updated_at"
    }

    public var inviteURL: URL? {
        guard let inviteURLString else { return nil }
        return URL(string: inviteURLString)
    }
}

public enum RemoteReferralClaimResult: String, Codable, Equatable {
    case claimed
    case alreadyClaimed = "already_claimed"
    case selfReferral = "self_referral"
    case duplicate = "duplicate"
    case pendingValidation = "pending_validation"
}

public struct RemoteReferralClaimResponse: Codable, Equatable {
    public let status: RemoteReferralClaimResult
    public let referral: RemoteReferralStatus
    public let message: String?

    public init(status: RemoteReferralClaimResult, referral: RemoteReferralStatus, message: String?) {
        self.status = status
        self.referral = referral
        self.message = message
    }
}

public struct RemoteReferralReward: Codable, Equatable {
    public let id: String
    public let bonusFreeScans: Int
    public let sourceCode: String?
    public let createdAt: Date

    public init(id: String, bonusFreeScans: Int, sourceCode: String?, createdAt: Date) {
        self.id = id
        self.bonusFreeScans = bonusFreeScans
        self.sourceCode = sourceCode
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bonusFreeScans = "bonus_free_scans"
        case sourceCode = "source_code"
        case createdAt = "created_at"
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
    public let debugMetadata: LocalAnalysisDebugMetadata?

    public init(
        analysisID: String,
        result: OnDeviceAnalysisResult,
        debugMetadata: LocalAnalysisDebugMetadata? = nil
    ) {
        self.analysisID = analysisID
        self.result = result
        self.debugMetadata = debugMetadata
    }
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
            return "Analysis is taking longer than expected. Please try again in a moment."
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
    let criterionInsights: [String: SkinCriterionInsight]?
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
        case criterionInsights
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
