import Foundation

public protocol SkinAnalysisService {
    func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult
}

public protocol SkinAnalysisRemoteClient {
    var isConfigured: Bool { get }
    func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult
}

public struct CompositeSkinAnalysisService: SkinAnalysisService {
    private let remoteClient: SkinAnalysisRemoteClient

    public init(remoteClient: SkinAnalysisRemoteClient = BackendSkinAnalysisClient()) {
        self.remoteClient = remoteClient
    }

    public func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult {
        if remoteClient.isConfigured {
            return try await remoteClient.analyze(imageData: imageData)
        }

        return try await Task.detached(priority: .userInitiated) {
            try OnDeviceSkinAnalyzer.analyze(imageData: imageData)
        }.value
    }
}
