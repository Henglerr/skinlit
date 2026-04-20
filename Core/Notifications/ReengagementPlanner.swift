import Foundation

public struct ReengagementPlanner {
    public static let identifierPrefix = "reengagement."
    public static let notificationThreadIdentifier = "reengagement"
    public static let productionCadence: [TimeInterval] = [86_400, 259_200, 604_800]
    public static let debugCadence: [TimeInterval] = [60, 180, 420]

    public let cadence: [TimeInterval]

    public init(cadence: [TimeInterval] = Self.defaultCadence) {
        self.cadence = cadence
    }

    public static var defaultCadence: [TimeInterval] {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        let isFastDebugEnabled = processInfo.environment["SKINLIT_DEBUG_FAST_NOTIFICATIONS"] == "1"
            || processInfo.environment["SKINSCORE_DEBUG_FAST_NOTIFICATIONS"] == "1"
            || processInfo.arguments.contains("-SkinLitDebugFastNotifications")
            || processInfo.arguments.contains("-SkinScoreDebugFastNotifications")
        return isFastDebugEnabled ? debugCadence : productionCadence
        #else
        return productionCadence
        #endif
    }

    public func stage(for context: ReengagementContext) -> ReengagementStage? {
        if !context.hasCompletedOnboarding {
            return context.resumeRoute == nil ? nil : .onboardingIncomplete
        }

        return context.hasAnyScan ? .hasScanHistory : .noScansYet
    }

    public func notifications(for context: ReengagementContext) -> [PlannedReengagementNotification] {
        guard let stage = stage(for: context) else { return [] }

        let messages = copy(for: stage)
        let intents = openIntent(for: stage)
        let identifiers = [
            "\(Self.identifierPrefix)day1",
            "\(Self.identifierPrefix)day3",
            "\(Self.identifierPrefix)day7"
        ]

        return zip(zip(identifiers, cadence), messages).map { pair, message in
            let (identifier, interval) = pair
            return PlannedReengagementNotification(
                id: identifier,
                title: message.title,
                body: message.body,
                interval: interval,
                stage: stage,
                openIntent: intents
            )
        }
    }

    private func openIntent(for stage: ReengagementStage) -> NotificationOpenIntent {
        switch stage {
        case .onboardingIncomplete:
            return .resumeOnboarding
        case .noScansYet:
            return .openFirstScan
        case .hasScanHistory:
            return .openHome
        }
    }

    private func copy(for stage: ReengagementStage) -> [(title: String, body: String)] {
        switch stage {
        case .onboardingIncomplete:
            return [
                ("Finish your setup", "Your SkinLit profile is almost ready. Open the app to complete it."),
                ("Your profile is waiting", "Finish setup and unlock tips tailored to your skin goals."),
                ("Pick up where you left off", "Come back anytime to finish your profile and start tracking.")
            ]
        case .noScansYet:
            return [
                ("Get your first skin score", "Your profile is ready. Open SkinLit to see your baseline."),
                ("See your AI baseline", "Start tracking your skin with a quick first scan."),
                ("Start tracking this week", "One scan is enough to begin your skin progress history.")
            ]
        case .hasScanHistory:
            return [
                ("Time for a fresh scan", "Open SkinLit and see how your skin is changing."),
                ("Track your progress", "A new scan helps compare your latest result with your last one."),
                ("Consistency beats guesswork", "Come back for a new skin score and keep your progress on track.")
            ]
        }
    }
}
