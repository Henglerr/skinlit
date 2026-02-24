import Foundation

public protocol SkinAnalysisService {
    func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult
}

public struct CompositeSkinAnalysisService: SkinAnalysisService {
    private let remoteAnalyzer: OpenAIVisionSkinAnalyzer

    public init(remoteAnalyzer: OpenAIVisionSkinAnalyzer = OpenAIVisionSkinAnalyzer()) {
        self.remoteAnalyzer = remoteAnalyzer
    }

    public func analyze(imageData: Data) async throws -> OnDeviceAnalysisResult {
        if remoteAnalyzer.isConfigured {
            return try await remoteAnalyzer.analyze(imageData: imageData)
        }
        return try await Task.detached(priority: .userInitiated) {
            try OnDeviceSkinAnalyzer.analyze(imageData: imageData)
        }.value
    }
}
