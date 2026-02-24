import Foundation
import SwiftData

public enum LocalStore {
    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LocalUser.self,
            OnboardingProfile.self,
            LocalAnalysis.self,
            AppLocalSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
