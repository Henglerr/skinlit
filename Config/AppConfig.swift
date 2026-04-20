import Foundation
import UIKit

public struct AppConfig {
    enum AppMode: String {
        case production
        case dev
    }

    static let appId          = "skinlit"
    static let appName        = "SkinLit"
    static let tagline        = "Track your skin's progress over time"
    static let scoreLabel     = "SkinLit Score"
    static let tiktokHandle   = "@skinlit"
    static let shareTemplate  = "My skin scored [SCORE]/10 | @skinlit"
    static let launchWebHost  = "skinlit.lat"
    static let scanConsentVersion = "2026-03-cloud-selfie-consent-v1"
    static let referralRewardThreshold = 2
    private static let installationIDAccount = "skinlit_installation_id"

    static let aiCriteria = [
        "Hydration and oiliness",
        "Texture and pores",
        "Uniformity and blemishes",
        "Luminosity and vitality"
    ]

    static let subscriptionProductIds = [
        "com.skinlit.pro.weekly",
        "com.skinlit.pro.monthly",
        "com.skinlit.pro.yearly"
    ]

    static let privacyPolicyURL = URL(string: "https://skinlit.lat/privacy")!
    static let termsURL = URL(string: "https://skinlit.lat/terms")!
    static let supportURL = URL(string: "https://skinlit.lat/support")!
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    static let paywallFeatures = [
        "Detailed score per criterion",
        "Full cosmetic AI skin analysis",
        "Weekly progress history",
        "Personalized routine suggestions",
        "Unlimited analyses"
    ]

    static let defaultFreeScanQuota = 10

    static let defaultOpenAIResponsesURL = URL(string: "https://api.openai.com/v1/responses")!
    static let defaultOpenAIVisionModel = "gpt-5.4-mini"
    static let defaultOpenAIVisionReasoningEffort = "high"
    static let skinAnalysisVersion = "skin-score-v6-category-insights"
    static let referenceCatalogVersion = "skin-score-reference-catalog-v1"
    static let centerReferenceIDs = ["ref-003", "ref-008", "ref-013", "ref-018", "ref-023"]
    static let imageQualityReasonValues = [
        "low_light",
        "overexposed",
        "blur",
        "heavy_filter",
        "heavy_makeup",
        "occlusion",
        "bad_angle",
        "multiple_faces"
    ]
    static let severityValues = ["none", "mild", "moderate", "severe"]

    static let sendsEmbeddedAnalysisContext = false
    static let requiresCalibratedCloudAnalysis = true
    static let allowsLegacyAnalysisRequestFallback = false

    static let embeddedSkinAnalysisContext = EmbeddedSkinAnalysisContext(
        version: skinAnalysisVersion,
        criteria: ["Hydration", "Texture", "Uniformity", "Luminosity"],
        systemPrompt: """
You are a strict cosmetic skin-quality evaluator for selfie-based skin scoring.

Judge only visible skin quality in the provided photo. Ignore attractiveness, hairstyle, expression, jewelry, clothing, and background. Good lighting, makeup, or filters must not inflate the result.

Use this rubric:
- Criteria: Hydration, Texture, Uniformity, Luminosity.
- Visible factors: active acne load, dryness/flaking, redness/irritation, old marks or pitting, rough texture.
- Range guides: 0-2 very poor, 2-4 poor, 4-6 mixed, 6-8 good, 8-10 exceptional and rare.

Rules:
- More active visible acne lowers the score.
- Dry or flaky skin lowers hydration and can cap the upper band.
- Old marks, pitting, or clear texture damage lower texture and uniformity and can cap the upper band.
- Scores above 8.0 are rare and require consistently strong criteria.
- If the image is not reliable enough, reject it instead of guessing.
""",
        visualReferencePolicy: """
Live scoring is backend-owned. The cloud pipeline may attach curated reference anchors at runtime for calibration, and any local copy here is documentation only.
""",
        scoreBands: [
            SkinAnalysisReferenceBand(
                label: "0-2",
                minScore: 0.0,
                maxScore: 2.0,
                guidance: "Very poor cosmetic skin quality with severe visible issues, aggressive inflammation, severe scarring, extreme roughness, or global irregularity.",
                anchors: [
                    SkinAnalysisReferenceAnchor(
                        id: "ref-001",
                        suggestedScore: 1.4,
                        description: "Close-up cheek with widespread active inflammatory lesions, strong redness, oily inflamed surface, and major texture disruption.",
                        assetSlot: "skin-ref-001"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-002",
                        suggestedScore: 1.6,
                        description: "Dense severe inflammatory acne across cheek and jaw with clustered lesions, strong redness, and highly uneven texture.",
                        assetSlot: "skin-ref-002"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-003",
                        suggestedScore: 1.8,
                        description: "Forehead with extensive inflammatory acne, irregular relief, deep marks, and clearly compromised uniformity.",
                        assetSlot: "skin-ref-003"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-004",
                        suggestedScore: 1.9,
                        description: "Side-profile severe acne and scarring across cheek and jaw with dense inflammatory coverage and poor texture.",
                        assetSlot: "skin-ref-004"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-005",
                        suggestedScore: 2.0,
                        description: "Extremely rough, deeply lined, visibly dehydrated skin with low luminosity and poor uniformity.",
                        assetSlot: "skin-ref-005"
                    )
                ]
            ),
            SkinAnalysisReferenceBand(
                label: "2-4",
                minScore: 2.0,
                maxScore: 4.0,
                guidance: "Poor cosmetic skin quality with clearly visible acne, redness, scarring, or texture damage, but less extreme than the worst bucket.",
                anchors: [
                    SkinAnalysisReferenceAnchor(
                        id: "ref-006",
                        suggestedScore: 2.3,
                        description: "Lower-face pustules and redness with poor uniformity and active inflammation, but less destructive than the worst anchors.",
                        assetSlot: "skin-ref-006"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-007",
                        suggestedScore: 2.8,
                        description: "Forehead and chin inflammatory acne with moderate spread, visible redness, and clearly reduced smoothness.",
                        assetSlot: "skin-ref-007"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-008",
                        suggestedScore: 3.2,
                        description: "Moderate inflammatory acne across forehead, cheeks, and chin with clear redness and visibly uneven skin quality.",
                        assetSlot: "skin-ref-008"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-009",
                        suggestedScore: 3.5,
                        description: "Diffuse cheek and chin redness with scattered breakouts and moderate texture loss.",
                        assetSlot: "skin-ref-009"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-010",
                        suggestedScore: 3.7,
                        description: "Scattered inflammatory lesions and redness with poor overall quality, but milder than the other 2-4 anchors.",
                        assetSlot: "skin-ref-010"
                    )
                ]
            ),
            SkinAnalysisReferenceBand(
                label: "4-6",
                minScore: 4.0,
                maxScore: 6.0,
                guidance: "Mid-range skin quality with visible but not severe acne, redness, dullness, or texture issues.",
                anchors: [
                    SkinAnalysisReferenceAnchor(
                        id: "ref-011",
                        suggestedScore: 4.4,
                        description: "Noticeable chin and lower-face acne with visible redness, but without severe full-face disruption.",
                        assetSlot: "skin-ref-011"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-012",
                        suggestedScore: 5.0,
                        description: "Mild forehead acne activity with otherwise acceptable tone and texture.",
                        assetSlot: "skin-ref-012"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-013",
                        suggestedScore: 5.2,
                        description: "Light forehead activity with soft residual redness and generally average skin quality.",
                        assetSlot: "skin-ref-013"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-014",
                        suggestedScore: 5.6,
                        description: "Scattered mild lesions with mostly balanced skin and limited texture impact.",
                        assetSlot: "skin-ref-014"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-015",
                        suggestedScore: 5.8,
                        description: "Mild residual acne and redness only, with mostly okay texture and tone.",
                        assetSlot: "skin-ref-015"
                    )
                ]
            ),
            SkinAnalysisReferenceBand(
                label: "6-8",
                minScore: 6.0,
                maxScore: 8.0,
                guidance: "Good skin quality overall with only small scattered blemishes or mild residual redness.",
                anchors: [
                    SkinAnalysisReferenceAnchor(
                        id: "ref-016",
                        suggestedScore: 6.6,
                        description: "Mostly even skin with a few visible forehead spots and mild imperfections.",
                        assetSlot: "skin-ref-016"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-017",
                        suggestedScore: 6.9,
                        description: "Small active spots on forehead, chin, and cheeks with otherwise balanced skin.",
                        assetSlot: "skin-ref-017"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-018",
                        suggestedScore: 7.1,
                        description: "Mild residual acne only, smooth texture overall, and limited redness.",
                        assetSlot: "skin-ref-018"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-019",
                        suggestedScore: 7.5,
                        description: "Very light imperfections with broadly smooth texture and good tone.",
                        assetSlot: "skin-ref-019"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-020",
                        suggestedScore: 7.7,
                        description: "Best of the good range with only minor visible issues and strong overall balance.",
                        assetSlot: "skin-ref-020"
                    )
                ]
            ),
            SkinAnalysisReferenceBand(
                label: "8-10",
                minScore: 8.0,
                maxScore: 10.0,
                guidance: "Excellent cosmetic skin quality with smooth texture, balanced tone, healthy luminosity, and little to no active inflammation.",
                anchors: [
                    SkinAnalysisReferenceAnchor(
                        id: "ref-021",
                        suggestedScore: 8.5,
                        description: "Mostly clear, glowy skin with only tiny faint forehead imperfections.",
                        assetSlot: "skin-ref-021"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-022",
                        suggestedScore: 8.8,
                        description: "Very even tone and texture with minimal residual marks.",
                        assetSlot: "skin-ref-022"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-023",
                        suggestedScore: 9.1,
                        description: "Smooth balanced skin with strong tone and luminosity.",
                        assetSlot: "skin-ref-023"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-024",
                        suggestedScore: 9.4,
                        description: "Near-clear skin with high smoothness and glow.",
                        assetSlot: "skin-ref-024"
                    ),
                    SkinAnalysisReferenceAnchor(
                        id: "ref-025",
                        suggestedScore: 9.6,
                        description: "Clearest anchor with minimal visible flaws, refined texture, and strong luminosity.",
                        assetSlot: "skin-ref-025"
                    )
                ]
            )
        ]
    )

    static func googleClientID(bundle: Bundle = .main) -> String {
        infoString(for: .googleClientID, bundle: bundle)
    }

    static func appMode(bundle: Bundle = .main) -> AppMode {
        let raw = infoString(for: .appMode, bundle: bundle).lowercased()
        return AppMode(rawValue: raw) ?? .production
    }

    static func isDeveloperModeEnabled(bundle: Bundle = .main) -> Bool {
        infoBool(for: .developerModeEnabled, bundle: bundle)
    }

    static func isUnlimitedScansMode(bundle: Bundle = .main) -> Bool {
        infoBool(for: .unlimitedScansMode, bundle: bundle)
    }

    static func isReferralsEnabled(bundle: Bundle = .main) -> Bool {
        infoBool(for: .referralsEnabled, bundle: bundle)
    }

    static func freeScanQuota(bundle: Bundle = .main) -> Int {
        return isUnlimitedScansMode(bundle: bundle) ? Int.max : defaultFreeScanQuota
    }

    static func backendBaseURL(bundle: Bundle = .main) -> String {
        infoString(for: .skinAnalysisAPIEndpoint, bundle: bundle)
    }

    static func appShareURL(bundle: Bundle = .main) -> URL? {
        let raw = infoString(for: .appShareURL, bundle: bundle)
        guard !raw.isEmpty, !raw.contains("$(") else { return nil }
        return URL(string: raw)
    }

    static func genericShareSheetItems(bundle: Bundle = .main) -> [Any] {
        if let resolvedURL = appShareURL(bundle: bundle) {
            return ["Track your cosmetic skin progress with SkinLit. \(resolvedURL.absoluteString)"]
        }
        return ["Track your cosmetic skin progress with SkinLit."]
    }

    static func referralShareSheetItems(
        inviteURL: URL? = nil,
        inviteCode: String? = nil,
        bundle: Bundle = .main
    ) -> [Any] {
        let normalizedCode = normalizedReferralCode(inviteCode)
        let resolvedURL = inviteURL ?? normalizedCode.flatMap { canonicalReferralURL(code: $0, bundle: bundle) }
        if let normalizedCode, let resolvedURL {
            return ["Join me on SkinLit and claim my launch code \(normalizedCode): \(resolvedURL.absoluteString)"]
        }
        if let normalizedCode {
            return ["Join me on SkinLit and claim my launch code \(normalizedCode)."]
        }
        if let resolvedURL {
            return ["Join me on SkinLit and claim my launch code: \(resolvedURL.absoluteString)"]
        }
        return ["Join me on SkinLit."]
    }

    static func isShareConfigured(bundle: Bundle = .main) -> Bool {
        appShareURL(bundle: bundle) != nil
    }

    static func canonicalReferralURL(code: String, bundle: Bundle = .main) -> URL? {
        guard let normalizedCode = normalizedReferralCode(code) else { return nil }

        if let baseURL = appShareURL(bundle: bundle),
           var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            components.path = "/referral/"
            components.queryItems = [
                URLQueryItem(name: "code", value: normalizedCode)
            ]
            components.fragment = nil
            return components.url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = launchWebHost
        components.path = "/referral/"
        components.queryItems = [
            URLQueryItem(name: "code", value: normalizedCode)
        ]
        return components.url
    }

    static func referralCode(from url: URL, bundle: Bundle = .main) -> String? {
        let expectedHosts = Set([
            appShareURL(bundle: bundle)?.host?.lowercased(),
            launchWebHost
        ].compactMap { $0 })

        guard let host = url.host?.lowercased(), expectedHosts.contains(host) else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2, pathComponents[0].lowercased() == "r" {
            return normalizedReferralCode(pathComponents[1])
        }

        if pathComponents.first?.lowercased() == "referral" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let code = components?.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value
            return normalizedReferralCode(code)
        }

        return nil
    }

    static func normalizedReferralCode(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 4 else { return nil }
        return cleaned
    }

    static func deviceLabel() -> String {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? UIDevice.current.model : name
    }

    static func installationID(keychainStore: KeychainStore = KeychainStore()) -> String {
        if let data = keychainStore.read(account: installationIDAccount),
           let existing = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        if let payload = generated.data(using: .utf8) {
            try? keychainStore.save(payload, account: installationIDAccount)
        }
        return generated
    }

    static func appVersion(bundle: Bundle = .main) -> String {
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(buildNumber)):
            return "\(version) (\(buildNumber))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(buildNumber)):
            return buildNumber
        default:
            return "1.0"
        }
    }

    static func openAIAPIKey(bundle: Bundle = .main) -> String {
        ""
    }

    static func openAIVisionModel(bundle: Bundle = .main) -> String {
        defaultOpenAIVisionModel
    }

    static func openAIVisionReasoningEffort(bundle: Bundle = .main) -> String {
        defaultOpenAIVisionReasoningEffort
    }

    static func skinAnalysisAPIEndpoint(bundle: Bundle = .main) -> String {
        infoString(for: .skinAnalysisAPIEndpoint, bundle: bundle)
    }

    static func skinAnalysisAPIAuthToken(bundle: Bundle = .main) -> String {
        ""
    }

    private enum InfoKey: String {
        case googleClientID = "GIDClientID"
        case skinAnalysisAPIEndpoint = "SkinAnalysisAPIEndpoint"
        case appShareURL = "AppShareURL"
        case appMode = "AppMode"
        case developerModeEnabled = "DeveloperModeEnabled"
        case unlimitedScansMode = "UnlimitedScansMode"
        case referralsEnabled = "ReferralsEnabled"
    }

    private static func infoString(for key: InfoKey, bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: key.rawValue) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func infoBool(for key: InfoKey, bundle: Bundle) -> Bool {
        let raw = infoString(for: key, bundle: bundle).lowercased()
        guard !raw.isEmpty, !raw.contains("$(") else { return false }
        return ["1", "true", "yes", "on", "enabled"].contains(raw)
    }

    static func detailedReferenceIDs(for predictedBand: String) -> [String] {
        switch predictedBand {
        case "0-2":
            return ["ref-001", "ref-002", "ref-003", "ref-004", "ref-005", "ref-006", "ref-007"]
        case "2-4":
            return ["ref-005", "ref-006", "ref-007", "ref-008", "ref-009", "ref-010", "ref-011"]
        case "4-6":
            return ["ref-010", "ref-011", "ref-012", "ref-013", "ref-014", "ref-015", "ref-016"]
        case "6-8":
            return ["ref-015", "ref-016", "ref-017", "ref-018", "ref-019", "ref-020", "ref-021"]
        case "8-10":
            return ["ref-019", "ref-020", "ref-021", "ref-022", "ref-023", "ref-024", "ref-025"]
        default:
            return centerReferenceIDs
        }
    }

    static func classificationPrompt(userContext: SkinAnalysisUserContext?) -> String {
        """
You are a strict cosmetic skin-quality evaluator for selfie-based skin scoring.

Task:
- Judge only the visible skin quality in the provided selfie.
- Compare the selfie against the attached reference images before deciding a band.
- Return only the closest score band, image quality status, and objective severity flags.

Never score or classify based on:
- facial attractiveness
- styling, hair, jewelry, clothing, expression, or background
- flattering lighting
- perceived age by itself

Lighting policy:
- Two user images are attached: one raw face crop and one lightly normalized face crop.
- Use the normalized image only to compensate for exposure and shadow.
- Never reward the skin for looking better only because lighting is flattering.
- If lighting, blur, occlusion, makeup, filters, or angle make the skin unreliable to judge, mark `image_quality_status` as `insufficient`.

Band calibration:
\(scoreBandPromptText)

Hard severity rules:
- Severe inflammatory acne or severe pitted scarring should almost always land in `0-2` or `2-4`.
- Moderate inflammation plus moderate texture irregularity should never be treated as high-quality skin.
- `8-10` is rare and requires visually exceptional smoothness, even tone, and strong luminosity.

User context below may help phrasing later, but it must not affect the classification itself:
\(userContextPromptBlock(userContext))
"""
    }

    static func detailedAssessmentPrompt(userContext: SkinAnalysisUserContext?) -> String {
        """
You are a strict cosmetic skin-quality evaluator for selfie-based skin scoring.

Task:
- Judge only visible skin quality from the attached selfie and reference anchors.
- Use the attached reference images as your primary visual anchors.
- Return criterion scores, a 2-4 sentence summary, detailed criterion insights, detected skin type, and objective severity flags.
- Do not return the final overall score. The app computes it deterministically.

Judging rules:
- Criteria are `Hydration`, `Texture`, `Uniformity`, and `Luminosity`.
- Score harshly when active inflammation, scarring, rough texture, redness, flaking, or dullness are obvious.
- Do not compensate a severe visible issue with generic compliments.
- High criterion scores must remain rare.

Lighting and quality policy:
- The raw crop is the main truth source.
- The normalized crop is only for recovering visibility lost to shadow or exposure.
- Never inflate scores because the normalized crop looks prettier.

Objective conditions:
- `active_inflammation`
- `scarring_pitting`
- `texture_irregularity`
- `redness_irritation`
- `dryness_flaking`

Severity scale for every condition: `none`, `mild`, `moderate`, `severe`.

Band calibration:
\(scoreBandPromptText)

User context can shape wording only, never the numeric judgement:
\(userContextPromptBlock(userContext))

Summary rule:
- Use 2-4 concise, specific sentences.
- Be honest and evidence-based.
- Summary and criterion insights are user-facing. Never mention reference IDs, anchors, band labels, ranking, comparisons, or calibration logic.
- For every criterion insight, include visible positives, visible potential negatives, and one focused routine recommendation.
"""
    }

    private static var scoreBandPromptText: String {
        embeddedSkinAnalysisContext.scoreBands
            .map { band in
                let anchors = band.anchors
                    .map { anchor in
                        "- \(anchor.id) (\(anchor.suggestedScore)): \(anchor.description)"
                    }
                    .joined(separator: "\n")
                return """
\(band.label): \(band.guidance)
\(anchors)
"""
            }
            .joined(separator: "\n\n")
    }

    private static func userContextPromptBlock(_ userContext: SkinAnalysisUserContext?) -> String {
        guard let userContext, !userContext.isEmpty else {
            return "- skin_types: []\n- goal: null\n- routine_level: null"
        }

        let skinTypes = userContext.skinTypes.isEmpty ? "[]" : userContext.skinTypes.joined(separator: ", ")
        let goal = userContext.goal ?? "null"
        let routineLevel = userContext.routineLevel ?? "null"
        return """
- skin_types: \(skinTypes)
- goal: \(goal)
- routine_level: \(routineLevel)
"""
    }
}
