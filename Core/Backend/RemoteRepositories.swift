import Foundation

public final class RemoteOnboardingRepository {
    private let client: ConvexBackendClient
    private let sessionService: BackendSessionService

    public init(
        client: ConvexBackendClient = ConvexBackendClient(),
        sessionService: BackendSessionService
    ) {
        self.client = client
        self.sessionService = sessionService
    }

    public func fetchProfile() async throws -> RemoteOnboardingProfile? {
        let session = try sessionService.requireCurrentSession()
        return try await client.fetchOnboarding(sessionToken: session.sessionToken)
    }

    public func saveProfile(skinTypes: [String], goal: String, routineLevel: String) async throws {
        let session = try sessionService.requireCurrentSession()
        try await client.saveOnboarding(
            sessionToken: session.sessionToken,
            skinTypes: skinTypes,
            goal: goal,
            routineLevel: routineLevel
        )
    }
}

public final class RemoteScanRepository: RemoteScanAnalyzing, SkinAnalysisQualityOverrideService {
    private static let scanJobTimeoutSeconds: TimeInterval = 180
    private static let scanJobPollIntervalNanoseconds: UInt64 = 1_000_000_000

    private let client: ConvexBackendClient
    private let sessionService: BackendSessionService

    public var isConfigured: Bool {
        client.isConfigured
    }

    public init(
        client: ConvexBackendClient = ConvexBackendClient(),
        sessionService: BackendSessionService
    ) {
        self.client = client
        self.sessionService = sessionService
    }

    public func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?
    ) async throws -> SkinAnalysisOutcome {
        try await analyze(
            imageData: imageData,
            imageHash: imageHash,
            userContext: userContext,
            ignoredQualityReasons: []
        )
    }

    public func analyze(
        imageData: Data,
        imageHash: String?,
        userContext: SkinAnalysisUserContext?,
        ignoredQualityReasons: Set<SkinImageQualityReason>
    ) async throws -> SkinAnalysisOutcome {
        let session = try sessionService.requireCurrentSession()
        let normalizedImageData = try FaceImageProcessor.normalizedVariant(from: imageData)
        let createdJob = try await client.createScanJob(
            sessionToken: session.sessionToken,
            rawImageData: imageData,
            normalizedImageData: normalizedImageData,
            imageHash: imageHash,
            userContext: userContext,
            ignoredQualityReasons: ignoredQualityReasons
        )
        let jobID = createdJob.jobID
        let debugSource: AnalysisDebugSource =
            createdJob.status == .succeeded ? .backendReuse : .remoteFresh

        let deadline = Date().addingTimeInterval(Self.scanJobTimeoutSeconds)
        while Date() < deadline {
            let job = try await client.fetchScanJob(sessionToken: session.sessionToken, jobID: jobID)
            switch job.status {
            case .queued, .running:
                try await Task.sleep(nanoseconds: Self.scanJobPollIntervalNanoseconds)
            case .rejected:
                let qualityReasons = Self.imageQualityReasons(
                    failureCode: job.failureCode,
                    failureMessage: job.failureMessage
                )
                if !qualityReasons.isEmpty {
                    let blockingReasons = qualityReasons.filter { !ignoredQualityReasons.contains($0) }
                    if blockingReasons.isEmpty,
                       let recoveredOutcome = try await fetchOverrideOutcomeIfReady(
                        sessionToken: session.sessionToken,
                        initialJob: job,
                        jobID: jobID,
                        debugSource: debugSource
                       ) {
                        return recoveredOutcome
                    }

                    throw SkinAnalysisRemoteError.insufficientImageQuality(
                        reasons: ignoredQualityReasons.isEmpty || blockingReasons.isEmpty
                            ? qualityReasons
                            : blockingReasons
                    )
                }

                throw BackendClientError.scanRejected(message: job.failureMessage ?? "This selfie could not be analyzed reliably.")
            case .failed:
                throw BackendClientError.requestFailed(
                    statusCode: 500,
                    message: job.failureMessage ?? "The backend could not finish this scan."
                )
            case .succeeded:
                guard let scanID = job.scanID else {
                    throw BackendClientError.invalidResponse
                }
                let scan = try await client.fetchScan(sessionToken: session.sessionToken, scanID: scanID)
                return SkinAnalysisOutcome(
                    analysisID: scan.id,
                    result: scan.asAnalysisResult,
                    debugMetadata: scan.debugMetadata(source: debugSource)
                )
            }
        }

        throw BackendClientError.jobTimedOut
    }

    private func fetchOverrideOutcomeIfReady(
        sessionToken: String,
        initialJob: RemoteScanJob,
        jobID: String,
        debugSource: AnalysisDebugSource
    ) async throws -> SkinAnalysisOutcome? {
        if let scanID = initialJob.scanID {
            let scan = try await client.fetchScan(sessionToken: sessionToken, scanID: scanID)
            return SkinAnalysisOutcome(
                analysisID: scan.id,
                result: scan.asAnalysisResult,
                debugMetadata: scan.debugMetadata(source: debugSource)
            )
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 750_000_000)
            let refreshedJob = try await client.fetchScanJob(sessionToken: sessionToken, jobID: jobID)
            if let scanID = refreshedJob.scanID {
                let scan = try await client.fetchScan(sessionToken: sessionToken, scanID: scanID)
                return SkinAnalysisOutcome(
                    analysisID: scan.id,
                    result: scan.asAnalysisResult,
                    debugMetadata: scan.debugMetadata(source: debugSource)
                )
            }

            if refreshedJob.status == .failed {
                break
            }
        }

        return nil
    }

    private static func imageQualityReasons(
        failureCode: String?,
        failureMessage: String?
    ) -> [SkinImageQualityReason] {
        let raw = [failureCode, failureMessage]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        guard !raw.isEmpty else { return [] }
        return SkinImageQualityReason.allCases.filter { raw.contains($0.rawValue) }
    }

    public func fetchRecentAnalyses() async throws -> [RemoteScanResult] {
        let session = try sessionService.requireCurrentSession()
        return try await client.fetchScans(sessionToken: session.sessionToken)
    }

    public func importLocalAnalyses(_ analyses: [LocalAnalysis]) async throws {
        guard !analyses.isEmpty else { return }
        let session = try sessionService.requireCurrentSession()
        let payload = analyses.compactMap { analysis -> RemoteScanImportItem? in
            let criteria = (try? JSONDecoder().decode([String: Double].self, from: Data(analysis.criteriaJSON.utf8))) ?? [:]
            return RemoteScanImportItem(
                clientScanId: analysis.id,
                score: analysis.score,
                summary: analysis.summary,
                skinTypeDetected: analysis.skinTypeDetected,
                criteria: [
                    "Hydration": criteria["Hydration"] ?? 0,
                    "Texture": criteria["Texture"] ?? 0,
                    "Uniformity": criteria["Uniformity"] ?? 0,
                    "Luminosity": criteria["Luminosity"] ?? 0
                ],
                criterionInsights: analysis.criterionInsights,
                observedConditions: SkinObservedConditions(
                    activeInflammation: .none,
                    scarringPitting: .none,
                    textureIrregularity: .none,
                    rednessIrritation: .none,
                    drynessFlaking: .none
                ),
                predictedBand: Self.predictedBand(for: analysis.score),
                imageQualityStatus: .ok,
                imageQualityReasons: [],
                analysisVersion: "local-guest-v1",
                referenceCatalogVersion: "local-none",
                model: "on-device",
                inputImageHash: analysis.imageHash,
                createdAt: ISO8601DateFormatter.backend.string(from: analysis.createdAt)
            )
        }
        try await client.importScans(sessionToken: session.sessionToken, scans: payload)
    }

    private static func predictedBand(for score: Double) -> String {
        switch score {
        case ..<2.0:
            return "0-2"
        case ..<4.0:
            return "2-4"
        case ..<6.0:
            return "4-6"
        case ..<8.0:
            return "6-8"
        default:
            return "8-10"
        }
    }
}

public final class RemoteJourneyRepository {
    private let client: ConvexBackendClient
    private let sessionService: BackendSessionService

    public init(
        client: ConvexBackendClient = ConvexBackendClient(),
        sessionService: BackendSessionService
    ) {
        self.client = client
        self.sessionService = sessionService
    }

    public func fetchLogs() async throws -> [RemoteJourneyLog] {
        let session = try sessionService.requireCurrentSession()
        return try await client.fetchJourney(sessionToken: session.sessionToken)
    }

    public func saveLog(_ log: RemoteJourneyLog) async throws {
        let session = try sessionService.requireCurrentSession()
        try await client.upsertJourneyLog(sessionToken: session.sessionToken, log: log)
    }

    public func deleteLog(dayKey: String) async throws {
        let session = try sessionService.requireCurrentSession()
        try await client.deleteJourneyLog(sessionToken: session.sessionToken, dayKey: dayKey)
    }

    public func importLocalLogs(_ logs: [SkinJourneyLog]) async throws {
        guard !logs.isEmpty else { return }
        let session = try sessionService.requireCurrentSession()
        let payload = logs.map { log in
            RemoteJourneyImportItem(
                dayKey: log.dayKey,
                dayStartAt: ISO8601DateFormatter.backend.string(from: log.dayStartAt),
                routineStepIDs: log.routineStepIDs,
                treatmentIDs: log.treatmentIDs,
                skinStatusIDs: log.skinStatusIDs,
                note: log.note,
                createdAt: ISO8601DateFormatter.backend.string(from: log.createdAt),
                updatedAt: ISO8601DateFormatter.backend.string(from: log.updatedAt)
            )
        }
        try await client.importJourney(sessionToken: session.sessionToken, logs: payload)
    }
}

public final class RemoteReferralRepository {
    private let client: ConvexBackendClient
    private let sessionService: BackendSessionService

    public init(
        client: ConvexBackendClient = ConvexBackendClient(),
        sessionService: BackendSessionService
    ) {
        self.client = client
        self.sessionService = sessionService
    }

    public func fetchStatus() async throws -> RemoteReferralStatus {
        let session = try sessionService.requireCurrentSession()
        return try await client.fetchReferralStatus(sessionToken: session.sessionToken)
    }

    public func createInvite() async throws -> RemoteReferralStatus {
        let session = try sessionService.requireCurrentSession()
        return try await client.createReferralInvite(sessionToken: session.sessionToken)
    }

    public func claimReferralCode(_ code: String) async throws -> RemoteReferralClaimResponse {
        let session = try sessionService.requireCurrentSession()
        return try await client.claimReferralCode(sessionToken: session.sessionToken, code: code)
    }

    public func fetchRewardLedger() async throws -> [RemoteReferralReward] {
        let session = try sessionService.requireCurrentSession()
        return try await client.fetchReferralRewards(sessionToken: session.sessionToken)
    }
}
