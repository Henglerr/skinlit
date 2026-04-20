import Foundation

public final class RemoteDataSyncService {
    private let remoteOnboardingRepository: RemoteOnboardingRepository
    private let remoteScanRepository: RemoteScanRepository
    private let remoteJourneyRepository: RemoteJourneyRepository

    public init(
        remoteOnboardingRepository: RemoteOnboardingRepository,
        remoteScanRepository: RemoteScanRepository,
        remoteJourneyRepository: RemoteJourneyRepository
    ) {
        self.remoteOnboardingRepository = remoteOnboardingRepository
        self.remoteScanRepository = remoteScanRepository
        self.remoteJourneyRepository = remoteJourneyRepository
    }

    public func synchronizeLocalCache(
        userId: String,
        localProfile: OnboardingProfile?,
        localAnalyses: [LocalAnalysis],
        localJourneyLogs: [SkinJourneyLog],
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        skinJourneyRepository: SkinJourneyRepository
    ) async throws {
        if let localProfile {
            try await remoteOnboardingRepository.saveProfile(
                skinTypes: localProfile.skinTypesCSV.components(separatedBy: "||").filter { !$0.isEmpty },
                goal: localProfile.goal,
                routineLevel: localProfile.routine
            )
        }

        try await remoteScanRepository.importLocalAnalyses(localAnalyses)
        try await remoteJourneyRepository.importLocalLogs(localJourneyLogs)

        if let remoteProfile = try await remoteOnboardingRepository.fetchProfile() {
            try await MainActor.run {
                try onboardingRepository.saveOnboarding(
                    userId: userId,
                    skinTypes: remoteProfile.skinTypes,
                    goal: remoteProfile.goal,
                    routine: remoteProfile.routineLevel
                )
            }
        }

        let remoteScans = try await remoteScanRepository.fetchRecentAnalyses()
        for scan in remoteScans {
            let criteriaData = try JSONEncoder().encode(scan.criteria)
            let criteriaJSON = String(data: criteriaData, encoding: .utf8) ?? "{}"
            let criterionInsightsJSON: String?
            if let criterionInsights = scan.criterionInsights {
                let criterionInsightsData = try JSONEncoder().encode(criterionInsights)
                criterionInsightsJSON = String(data: criterionInsightsData, encoding: .utf8)
            } else {
                criterionInsightsJSON = nil
            }
            let debugMetadataData = try JSONEncoder().encode(scan.debugMetadata(source: .remoteSynced))
            let debugMetadataJSON = String(data: debugMetadataData, encoding: .utf8)
            try await MainActor.run {
                try analysisRepository.saveAnalysis(
                    id: scan.id,
                    userId: userId,
                    score: scan.score,
                    summary: scan.summary,
                    skinTypeDetected: scan.skinTypeDetected,
                    imageHash: nil,
                    criteriaJSON: criteriaJSON,
                    criterionInsightsJSON: criterionInsightsJSON,
                    debugMetadataJSON: debugMetadataJSON,
                    createdAt: scan.createdAt
                )
            }
        }

        let remoteLogs = try await remoteJourneyRepository.fetchLogs()
        for log in remoteLogs {
            try await MainActor.run {
                try skinJourneyRepository.upsertLog(
                    userId: userId,
                    date: log.dayStartAt,
                    routineStepIDs: log.routineStepIDs,
                    treatmentIDs: log.treatmentIDs,
                    skinStatusIDs: log.skinStatusIDs,
                    note: log.note
                )
            }
        }
    }
}
