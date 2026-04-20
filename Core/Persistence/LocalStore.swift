import Foundation
import SwiftData

public protocol AnalysisPhotoStoring {
    func saveProcessedPhoto(_ imageData: Data, analysisID: String) throws -> String
    func deletePhoto(relativePath: String) throws
    func fileURL(forRelativePath relativePath: String) -> URL?
}

public struct FileSystemAnalysisPhotoStore: AnalysisPhotoStoring {
    private static let photosDirectoryName = "AnalysisPhotos"

    private let fileManager: FileManager
    private let applicationSupportURLProvider: () throws -> URL

    public init(
        fileManager: FileManager = .default,
        applicationSupportURLProvider: (() throws -> URL)? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURLProvider = applicationSupportURLProvider ?? {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
    }

    public func saveProcessedPhoto(_ imageData: Data, analysisID: String) throws -> String {
        let relativePath = Self.relativePath(for: analysisID)
        let destinationURL = try resolvedFileURL(forRelativePath: relativePath)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try imageData.write(to: destinationURL, options: .atomic)
        return relativePath
    }

    public func deletePhoto(relativePath: String) throws {
        let fileURL = try resolvedFileURL(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    public func fileURL(forRelativePath relativePath: String) -> URL? {
        try? resolvedFileURL(forRelativePath: relativePath)
    }

    public static func fileURL(forRelativePath relativePath: String?) -> URL? {
        guard
            let relativePath,
            !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let store = FileSystemAnalysisPhotoStore()
        return store.fileURL(forRelativePath: relativePath)
    }

    private func resolvedFileURL(forRelativePath relativePath: String) throws -> URL {
        try applicationSupportURLProvider()
            .appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func relativePath(for analysisID: String) -> String {
        let safeAnalysisID = analysisID.replacingOccurrences(
            of: #"[^A-Za-z0-9_-]"#,
            with: "-",
            options: .regularExpression
        )
        return "\(photosDirectoryName)/\(safeAnalysisID).jpg"
    }
}

public enum LocalStore {
    public enum StorageMode {
        case persistent
        case inMemory
    }

    public static func makeContainer(storageMode: StorageMode = .persistent) throws -> ModelContainer {
        let schema = Schema([
            LocalUser.self,
            OnboardingDraft.self,
            OnboardingProfile.self,
            LocalAnalysis.self,
            SkinJourneyLog.self,
            AppLocalSettings.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storageMode == .inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
