import Foundation

public struct AppConfig {
    static let appId          = "skin-score"
    static let appName        = "Skin Score"
    static let tagline        = "Discover your skin score in seconds"
    static let scoreLabel     = "Skin Score"
    static let tiktokHandle   = "@skinscore"
    static let shareTemplate  = "My skin scored [SCORE]/10 ✨ | @skinscore"

    static let aiCriteria = [
        "Hydration and oiliness",
        "Texture and pores",
        "Uniformity and blemishes",
        "Luminosity and vitality"
    ]

    static let subscriptionProductIds = [
        "com.skinscore.pro.weekly",
        "com.skinscore.pro.monthly",
        "com.skinscore.pro.yearly"
    ]

    static let privacyPolicyURL = URL(string: "https://example.com/privacy")!
    static let termsURL = URL(string: "https://example.com/terms")!
    static let supportURL = URL(string: "https://example.com/support")!

    static let paywallFeatures = [
        "Detailed score by criterion (hydration, texture, blemishes, luminosity)",
        "Full AI analysis — know exactly what to improve",
        "Progress tracking — see your skin evolving over time",
        "Unlimited community feed",
        "Notifications when your photo is rated",
        "Full Skin Profile — discover your real skin type",
        "Unlimited analyses"
    ]

    static func googleClientID(bundle: Bundle = .main) -> String {
        infoString(for: .googleClientID, bundle: bundle)
    }

    static func skinAnalysisAPIEndpoint(bundle: Bundle = .main) -> String {
        infoString(for: .skinAnalysisAPIEndpoint, bundle: bundle)
    }

    static func skinAnalysisAPIAuthToken(bundle: Bundle = .main) -> String {
        infoString(for: .skinAnalysisAPIAuthToken, bundle: bundle)
    }

    private enum InfoKey: String {
        case googleClientID = "GIDClientID"
        case skinAnalysisAPIEndpoint = "SkinAnalysisAPIEndpoint"
        case skinAnalysisAPIAuthToken = "SkinAnalysisAPIAuthToken"
    }

    private static func infoString(for key: InfoKey, bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: key.rawValue) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
