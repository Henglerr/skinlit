import Foundation

public protocol SkinAnalysisService {
    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome
}

public protocol RemoteScanAnalyzing {
    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome
}

public protocol SkinAnalysisRemoteClient {
    var isConfigured: Bool { get }
    func analyze(imageData: Data, userContext: SkinAnalysisUserContext?) async throws -> OnDeviceAnalysisResult
}

public protocol SkinAnalysisQualityOverrideService {
    var isConfigured: Bool { get }
    func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?,
        ignoredQualityReasons: Set<SkinImageQualityReason>
    ) async throws -> SkinAnalysisOutcome
}

public struct SkinAnalysisUserContext: Codable, Equatable {
    public let skinTypes: [String]
    public let goal: String?
    public let routineLevel: String?

    public init(
        skinTypes: [String],
        goal: String?,
        routineLevel: String?
    ) {
        self.skinTypes = skinTypes
        self.goal = goal
        self.routineLevel = routineLevel
    }

    public var isEmpty: Bool {
        skinTypes.isEmpty && goal == nil && routineLevel == nil
    }

    enum CodingKeys: String, CodingKey {
        case skinTypes = "skin_types"
        case goal
        case routineLevel = "routine_level"
    }
}

public struct SkinAnalysisReferenceAnchor: Codable, Equatable {
    public let id: String
    public let suggestedScore: Double
    public let description: String
    public let assetSlot: String?

    public init(
        id: String,
        suggestedScore: Double,
        description: String,
        assetSlot: String? = nil
    ) {
        self.id = id
        self.suggestedScore = suggestedScore
        self.description = description
        self.assetSlot = assetSlot
    }

    enum CodingKeys: String, CodingKey {
        case id
        case suggestedScore = "suggested_score"
        case description
        case assetSlot = "asset_slot"
    }
}

public struct SkinAnalysisReferenceBand: Codable, Equatable {
    public let label: String
    public let minScore: Double
    public let maxScore: Double
    public let guidance: String
    public let anchors: [SkinAnalysisReferenceAnchor]

    public init(
        label: String,
        minScore: Double,
        maxScore: Double,
        guidance: String,
        anchors: [SkinAnalysisReferenceAnchor]
    ) {
        self.label = label
        self.minScore = minScore
        self.maxScore = maxScore
        self.guidance = guidance
        self.anchors = anchors
    }

    enum CodingKeys: String, CodingKey {
        case label
        case minScore = "min_score"
        case maxScore = "max_score"
        case guidance
        case anchors
    }
}

public struct EmbeddedSkinAnalysisContext: Codable, Equatable {
    public let version: String
    public let criteria: [String]
    public let systemPrompt: String
    public let visualReferencePolicy: String
    public let scoreBands: [SkinAnalysisReferenceBand]
    public let userContext: SkinAnalysisUserContext?

    public init(
        version: String,
        criteria: [String],
        systemPrompt: String,
        visualReferencePolicy: String,
        scoreBands: [SkinAnalysisReferenceBand],
        userContext: SkinAnalysisUserContext? = nil
    ) {
        self.version = version
        self.criteria = criteria
        self.systemPrompt = systemPrompt
        self.visualReferencePolicy = visualReferencePolicy
        self.scoreBands = scoreBands
        self.userContext = userContext
    }

    public func with(userContext: SkinAnalysisUserContext?) -> EmbeddedSkinAnalysisContext {
        EmbeddedSkinAnalysisContext(
            version: version,
            criteria: criteria,
            systemPrompt: systemPrompt,
            visualReferencePolicy: visualReferencePolicy,
            scoreBands: scoreBands,
            userContext: userContext?.isEmpty == true ? nil : userContext
        )
    }

    enum CodingKeys: String, CodingKey {
        case version
        case criteria
        case systemPrompt = "system_prompt"
        case visualReferencePolicy = "visual_reference_policy"
        case scoreBands = "score_bands"
        case userContext = "user_context"
    }
}

public enum SkinConditionSeverity: String, Codable, CaseIterable {
    case none
    case mild
    case moderate
    case severe
}

public enum SkinImageQualityStatus: String, Codable {
    case ok
    case insufficient
}

public enum SkinImageQualityReason: String, Codable, CaseIterable {
    case noFace = "no_face"
    case lowLight = "low_light"
    case overexposed
    case blur
    case heavyFilter = "heavy_filter"
    case heavyMakeup = "heavy_makeup"
    case occlusion
    case badAngle = "bad_angle"
    case multipleFaces = "multiple_faces"

    public var userFacingDescription: String {
        switch self {
        case .noFace:
            return "no face detected"
        case .lowLight:
            return "low light"
        case .overexposed:
            return "overexposed lighting"
        case .blur:
            return "blur"
        case .heavyFilter:
            return "heavy filter"
        case .heavyMakeup:
            return "heavy makeup"
        case .occlusion:
            return "face occlusion"
        case .badAngle:
            return "bad angle"
        case .multipleFaces:
            return "multiple faces"
        }
    }
}

public struct SkinObservedConditions: Codable, Equatable {
    public let activeInflammation: SkinConditionSeverity
    public let scarringPitting: SkinConditionSeverity
    public let textureIrregularity: SkinConditionSeverity
    public let rednessIrritation: SkinConditionSeverity
    public let drynessFlaking: SkinConditionSeverity

    public init(
        activeInflammation: SkinConditionSeverity,
        scarringPitting: SkinConditionSeverity,
        textureIrregularity: SkinConditionSeverity,
        rednessIrritation: SkinConditionSeverity,
        drynessFlaking: SkinConditionSeverity
    ) {
        self.activeInflammation = activeInflammation
        self.scarringPitting = scarringPitting
        self.textureIrregularity = textureIrregularity
        self.rednessIrritation = rednessIrritation
        self.drynessFlaking = drynessFlaking
    }

    enum CodingKeys: String, CodingKey {
        case activeInflammation = "active_inflammation"
        case scarringPitting = "scarring_pitting"
        case textureIrregularity = "texture_irregularity"
        case rednessIrritation = "redness_irritation"
        case drynessFlaking = "dryness_flaking"
    }
}

public struct SkinBandClassifierResponse: Decodable, Equatable {
    public let analysisVersion: String
    public let imageQualityStatus: SkinImageQualityStatus
    public let imageQualityReasons: [SkinImageQualityReason]
    public let predictedBand: String
    public let observedConditions: SkinObservedConditions

    enum CodingKeys: String, CodingKey {
        case analysisVersion = "analysis_version"
        case imageQualityStatus = "image_quality_status"
        case imageQualityReasons = "image_quality_reasons"
        case predictedBand = "predicted_band"
        case observedConditions = "observed_conditions"
    }
}

public struct SkinDetailedAssessmentResponse: Decodable, Equatable {
    public let analysisVersion: String
    public let summary: String
    public let skinTypeDetected: String
    public let criteria: [String: Double]
    public let criterionInsights: [String: SkinCriterionInsight]?
    public let observedConditions: SkinObservedConditions

    enum CodingKeys: String, CodingKey {
        case analysisVersion = "analysis_version"
        case summary
        case skinTypeDetected = "skin_type_detected"
        case criteria
        case criterionInsights = "criterion_insights"
        case observedConditions = "observed_conditions"
    }
}

public struct SkinReferenceAsset: Equatable {
    public let anchor: SkinAnalysisReferenceAnchor
    public let bandLabel: String
    public let imageData: Data
    public let mimeType: String

    public init(
        anchor: SkinAnalysisReferenceAnchor,
        bandLabel: String,
        imageData: Data,
        mimeType: String
    ) {
        self.anchor = anchor
        self.bandLabel = bandLabel
        self.imageData = imageData
        self.mimeType = mimeType
    }
}

public struct SkinReferenceCatalog {
    public let version: String
    public let bands: [SkinAnalysisReferenceBand]
    private let assetsByID: [String: SkinReferenceAsset]

    public init(
        version: String,
        bands: [SkinAnalysisReferenceBand],
        assets: [SkinReferenceAsset]
    ) {
        self.version = version
        self.bands = bands
        self.assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.anchor.id, $0) })
    }

    public init(bundle: Bundle = .main) throws {
        let bands = AppConfig.embeddedSkinAnalysisContext.scoreBands
        var assets: [SkinReferenceAsset] = []
        var missingIDs: [String] = []

        for band in bands {
            for anchor in band.anchors {
                if let asset = Self.resolveAsset(anchor: anchor, bandLabel: band.label, bundle: bundle) {
                    assets.append(asset)
                } else {
                    missingIDs.append(anchor.id)
                }
            }
        }

        if !missingIDs.isEmpty {
            throw SkinAnalysisRemoteError.referenceCatalogIncomplete(missingIDs: missingIDs)
        }

        self.init(
            version: AppConfig.referenceCatalogVersion,
            bands: bands,
            assets: assets
        )
    }

    public func validateRequiredAssets() throws {
        let expectedIDs = bands.flatMap(\.anchors).map(\.id)
        let missing = expectedIDs.filter { assetsByID[$0] == nil }
        if !missing.isEmpty {
            throw SkinAnalysisRemoteError.referenceCatalogIncomplete(missingIDs: missing)
        }
    }

    public func assets(for ids: [String]) throws -> [SkinReferenceAsset] {
        var resolved: [SkinReferenceAsset] = []
        var missing: [String] = []

        for id in ids {
            if let asset = assetsByID[id] {
                resolved.append(asset)
            } else {
                missing.append(id)
            }
        }

        if !missing.isEmpty {
            throw SkinAnalysisRemoteError.referenceCatalogIncomplete(missingIDs: missing)
        }

        return resolved
    }

    private static func resolveAsset(
        anchor: SkinAnalysisReferenceAnchor,
        bandLabel: String,
        bundle: Bundle
    ) -> SkinReferenceAsset? {
        let candidates = [anchor.id, anchor.assetSlot].compactMap { $0 }
        let extensions = ["jpg", "jpeg", "png", "webp", "heic"]

        for candidate in candidates {
            for fileExtension in extensions {
                if let url = bundle.url(forResource: candidate, withExtension: fileExtension, subdirectory: "SkinReferences"),
                   let data = try? Data(contentsOf: url) {
                    return SkinReferenceAsset(
                        anchor: anchor,
                        bandLabel: bandLabel,
                        imageData: data,
                        mimeType: mimeType(for: fileExtension)
                    )
                }

                if let url = bundle.url(forResource: candidate, withExtension: fileExtension),
                   let data = try? Data(contentsOf: url) {
                    return SkinReferenceAsset(
                        anchor: anchor,
                        bandLabel: bandLabel,
                        imageData: data,
                        mimeType: mimeType(for: fileExtension)
                    )
                }
            }
        }

        return nil
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }
}

public enum SkinScoreComputation {
    public static func finalScore(
        criteria: [String: Double],
        observedConditions: SkinObservedConditions
    ) -> Double {
        let hydration = clamp(criteria["Hydration"] ?? 0, min: 0, max: 10)
        let texture = clamp(criteria["Texture"] ?? 0, min: 0, max: 10)
        let uniformity = clamp(criteria["Uniformity"] ?? 0, min: 0, max: 10)
        let luminosity = clamp(criteria["Luminosity"] ?? 0, min: 0, max: 10)

        var score =
            hydration * 0.20 +
            texture * 0.30 +
            uniformity * 0.30 +
            luminosity * 0.20

        let values = [hydration, texture, uniformity, luminosity]
        if values.contains(where: { $0 <= 2.0 }) {
            score -= 1.2
        }
        if values.contains(where: { $0 <= 3.0 }) {
            score -= 0.8
        }
        if values.filter({ $0 < 5.0 }).count >= 2 {
            score -= 0.4
        }

        let conditions = observedConditions
        if conditions.activeInflammation == .severe || conditions.scarringPitting == .severe {
            score = min(score, 3.5)
        } else if conditions.activeInflammation == .moderate && conditions.textureIrregularity == .moderate {
            score = min(score, 5.8)
        }

        if conditions.rednessIrritation == .moderate || conditions.drynessFlaking == .moderate {
            score = min(score, 6.4)
        }

        let qualifiesForEightPlus =
            conditions.activeInflammation == .none || conditions.activeInflammation == .mild
        let canEnterExcellentBand =
            qualifiesForEightPlus &&
            conditions.scarringPitting == .none &&
            texture >= 8.0 &&
            uniformity >= 8.0 &&
            luminosity >= 7.5
        if !canEnterExcellentBand {
            score = min(score, 7.9)
        }

        return round1(clamp(score, min: 0, max: 10))
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

public struct CompositeSkinAnalysisService: SkinAnalysisService {
    private let remoteRepository: RemoteScanAnalyzing

    public init(remoteRepository: RemoteScanAnalyzing) {
        self.remoteRepository = remoteRepository
    }

    public func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome {
        try await remoteRepository.analyze(
            imageData: imageData,
            imageHash: imageHash,
            userContext: userContext
        )
    }
}
