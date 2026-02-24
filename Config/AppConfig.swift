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
