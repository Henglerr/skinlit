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

public final class RemoteScanRepository: RemoteScanAnalyzing {
    private let client: ConvexBackendClient
    private let sessionService: BackendSessionService

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
        let session = try sessionService.requireCurrentSession()
        let normalizedImageData = try FaceImageProcessor.normalizedVariant(from: imageData)
        let jobID = try await client.createScanJob(
            sessionToken: session.sessionToken,
            rawImageData: imageData,
            normalizedImageData: normalizedImageData,
            imageHash: imageHash,
            userContext: userContext
        )

        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 45 {
            let job = try await client.fetchScanJob(sessionToken: session.sessionToken, jobID: jobID)
            switch job.status {
            case .queued, .running:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            case .rejected:
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
                    result: scan.asAnalysisResult
                )
            }
        }

        throw BackendClientError.jobTimedOut
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
