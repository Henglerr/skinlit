import SwiftUI

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
}
