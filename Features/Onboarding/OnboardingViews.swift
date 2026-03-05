import SwiftUI
import StoreKit

private let onboardingHorizontalPadding: CGFloat = 20
private let onboardingButtonHorizontalPadding: CGFloat = 20
private let onboardingListHorizontalInset: CGFloat = 6
private let onboardingListBottomInset: CGFloat = 16

private struct OnboardingOptionsScroll<Content: View>: View {
    let topPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(topPadding: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.topPadding = topPadding
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, onboardingListHorizontalInset)
                .padding(.top, topPadding)
                .padding(.bottom, onboardingListBottomInset)
        }
        .scrollClipDisabled()
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
    }
}

struct OnboardingGenderView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedGender: String? = nil
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30

    let genders = ["Female", "Male", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProgressBar(currentStep: 1, totalSteps: 5)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("What's your gender?")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
            }
            .padding(.top, 8)
            .opacity(contentOpacity)
            .offset(y: slideOffset)

            OnboardingOptionsScroll(topPadding: 8) {
                VStack(spacing: 16) {
                    ForEach(genders.indices, id: \.self) { index in
                        let gender = genders[index]
                        GoalCard(
                            title: gender,
                            symbolName: nil,
                            description: "",
                            isSelected: selectedGender == gender
                        ) {
                            selectedGender = gender
                        }
                        .opacity(contentOpacity)
                        .offset(y: slideOffset)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05 + 0.1), value: contentOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, onboardingHorizontalPadding)
        .background(
            ZStack {
                AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
                Circle()
                    .fill(AppTheme.shared.current.colors.accentSoft)
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: -150, y: -250)
            }
        )
        .navigationBarHidden(true)
        .onAppear {
            if let savedGender = appState.onboardingDraftGender {
                selectedGender = savedGender
            }
            withAnimation(.easeOut(duration: 0.8)) {
                contentOpacity = 1.0
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)

                PrimaryButton("Continue", isEnabled: selectedGender != nil) {
                    appState.setOnboardingGender(selectedGender)
                    appState.navigate(to: .onboardingTheme)
                }
                .padding(.horizontal, onboardingButtonHorizontalPadding)
                .padding(.bottom, 32)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
    }
}

struct OnboardingThemeView: View {
    @EnvironmentObject var appState: AppState
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30

    let themes = [
        ("pastel", "Pastel Aesthetic", "paintpalette.fill", "Light, soft, and vibrant pinks"),
        ("purple", "Dark Purple", "moon.stars.fill", "Deep, elegant, and dark purple")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProgressBar(currentStep: 2, totalSteps: 5)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Choose your aesthetic")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                
                Text("You can change this anytime")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }
            .padding(.top, 8)
            .opacity(contentOpacity)
            .offset(y: slideOffset)

            OnboardingOptionsScroll(topPadding: 8) {
                VStack(spacing: 16) {
                    ForEach(themes.indices, id: \.self) { index in
                        let theme = themes[index]
                        GoalCard(
                            title: theme.1,
                            symbolName: theme.2,
                            description: theme.3,
                            isSelected: appState.appTheme == theme.0
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                appState.appTheme = theme.0
                            }
                        }
                        .opacity(contentOpacity)
                        .offset(y: slideOffset)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05 + 0.1), value: contentOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, onboardingHorizontalPadding)
        .background(
            ZStack {
                AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
                Circle()
                    .fill(AppTheme.shared.current.colors.accentSoft)
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: 200, y: 100)
            }
        )
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                contentOpacity = 1.0
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)

                PrimaryButton("Continue") {
                    appState.completeOnboardingThemeSelection()
                    appState.navigate(to: .onboardingSkintype)
                }
                .padding(.horizontal, onboardingButtonHorizontalPadding)
                .padding(.bottom, 32)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
    }
}

struct OnboardingSkintypeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTypes: Set<String> = []
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30

    let skinTypes = [
        ("Normal", "checkmark.circle.fill", "Balanced, fine pores"),
        ("Oily", "drop.fill", "Excess shine, large pores"),
        ("Dry", "sun.max.fill", "Flakiness, tight feeling"),
        ("Combination", "circle.lefthalf.filled", "Oily T-zone, dry cheeks"),
        ("Sensitive", "hand.raised.fill", "Redness, easy irritation"),
        ("Acne-prone", "scope", "Blackheads, breakouts"),
        ("Mature", "clock.fill", "Fine lines, loss of firmness"),
        ("Hyperpigmented", "moon.fill", "Dark spots, uneven tone")
    ]

    let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressBar(currentStep: 3, totalSteps: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("What's your skin type?")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)

                Text("You can choose more than one")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
            }
            .padding(.top, 4)
            .opacity(contentOpacity)
            .offset(y: slideOffset)

            OnboardingOptionsScroll(topPadding: 4) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(skinTypes.indices, id: \.self) { index in
                        let type = skinTypes[index]
                        SkinTypeChip(
                            symbolName: type.1,
                            title: type.0,
                            description: type.2,
                            isSelected: selectedTypes.contains(type.0)
                        ) {
                            if selectedTypes.contains(type.0) {
                                selectedTypes.remove(type.0)
                            } else {
                                selectedTypes.insert(type.0)
                            }
                        }
                        .opacity(contentOpacity)
                        .offset(y: slideOffset)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05 + 0.1), value: contentOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, onboardingHorizontalPadding)
        .background(
            ZStack {
                AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
                Circle()
                    .fill(AppTheme.shared.current.colors.accentSoft)
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: -150, y: -250)
            }
        )
        .navigationBarHidden(true)
        .onAppear {
            if !appState.onboardingDraftSkinTypes.isEmpty {
                selectedTypes = appState.onboardingDraftSkinTypes
            }
            withAnimation(.easeOut(duration: 0.8)) {
                contentOpacity = 1.0
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)

                PrimaryButton("Continue", isEnabled: !selectedTypes.isEmpty) {
                    appState.setOnboardingSkinTypes(selectedTypes)
                    appState.navigate(to: .onboardingGoal)
                }
                .padding(.horizontal, onboardingButtonHorizontalPadding)
                .padding(.bottom, 32)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
    }
}

struct OnboardingGoalView: View {
    @Environment(\.requestReview) var requestReview
    @EnvironmentObject var appState: AppState
    @State private var selectedGoal: String? = nil
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30
    @State private var showNotificationPrePrompt = false
    
    let goals = [
        ("Hydration", "drop.fill", "Want more hydrated and soft skin"),
        ("Glow", "sparkles", "Want that natural glow"),
        ("Acne Control", "scope", "Want to control breakouts and blemishes"),
        ("Anti-aging", "clock.fill", "Want to reduce fine lines and firmness"),
        ("Even Tone", "circle.lefthalf.filled", "Want a more uniform skin tone"),
        ("Just Rating", "chart.bar.fill", "I'll just rate other people's skin")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressBar(currentStep: 4, totalSteps: 6)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("What's your main goal?")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
            }
            .padding(.top, 4)
            .opacity(contentOpacity)
            .offset(y: slideOffset)

            OnboardingOptionsScroll(topPadding: 8) {
                VStack(spacing: 10) {
                    ForEach(goals.indices, id: \.self) { index in
                        let goal = goals[index]
                        GoalCard(
                            title: goal.0,
                            symbolName: goal.1,
                            description: goal.2,
                            isSelected: selectedGoal == goal.0
                        ) {
                            selectedGoal = goal.0
                        }
                        .opacity(contentOpacity)
                        .offset(y: slideOffset)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05 + 0.1), value: contentOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, onboardingHorizontalPadding)
        .background(
            ZStack {
                AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
                Circle()
                    .fill(AppTheme.shared.current.colors.accentSoft)
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: 200, y: 100)
            }
        )
        .navigationBarHidden(true)
        .onAppear {
            if let savedGoal = appState.onboardingDraftGoal {
                selectedGoal = savedGoal
            }
            withAnimation(.easeOut(duration: 0.8)) {
                contentOpacity = 1.0
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)

                PrimaryButton("Continue", isEnabled: selectedGoal != nil) {
                    appState.setOnboardingGoal(selectedGoal)
                    if appState.shouldPromptForNotificationPermission {
                        showNotificationPrePrompt = true
                    } else {
                        appState.navigate(to: .onboardingRoutine)
                    }
                }
                .padding(.horizontal, onboardingButtonHorizontalPadding)
                .padding(.bottom, 32)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
        .alert("Stay on track?", isPresented: $showNotificationPrePrompt) {
            Button("Not now", role: .cancel) {
                Task {
                    await appState.recordNotificationSoftDecline()
                    appState.navigate(to: .onboardingRoutine)
                }
            }

            Button("Allow reminders") {
                Task {
                    await appState.requestNotificationAuthorizationFromOnboarding()
                    appState.navigate(to: .onboardingRoutine)
                }
            }
        } message: {
            Text("We can remind you to finish setup and come back for your next Skin Score.")
        }
    }
}

struct OnboardingRoutineView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRoutine: String? = nil
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30

    let routines = [
        ("Beginner", "leaf.fill", "Moisturizer and SPF, that's it"),
        ("Basic", "checkmark.seal.fill", "Cleanser + moisturizer + SPF"),
        ("Advanced", "slider.horizontal.3", "Serums, acids, retinol..."),
        ("No routine", "minus.circle.fill", "Starting from zero")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProgressBar(currentStep: 5, totalSteps: 6)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("How's your current routine?")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
            }
            .padding(.top, 8)
            .opacity(contentOpacity)
            .offset(y: slideOffset)

            OnboardingOptionsScroll(topPadding: 8) {
                VStack(spacing: 16) {
                    ForEach(routines.indices, id: \.self) { index in
                        let routine = routines[index]
                        RoutineCard(
                            title: routine.0,
                            symbolName: routine.1,
                            description: routine.2,
                            isSelected: selectedRoutine == routine.0
                        ) {
                            selectedRoutine = routine.0
                        }
                        .opacity(contentOpacity)
                        .offset(y: slideOffset)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05 + 0.1), value: contentOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, onboardingHorizontalPadding)
        .background(
            ZStack {
                AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
                Circle()
                    .fill(AppTheme.shared.current.colors.accentSoft)
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: -200, y: 300)
            }
        )
        .navigationBarHidden(true)
        .onAppear {
            if let savedRoutine = appState.onboardingDraftRoutine {
                selectedRoutine = savedRoutine
            }
            withAnimation(.easeOut(duration: 0.8)) {
                contentOpacity = 1.0
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppTheme.shared.current.colors.bgPrimary.opacity(0), AppTheme.shared.current.colors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)

                PrimaryButton("Continue", isEnabled: selectedRoutine != nil) {
                    appState.setOnboardingRoutine(selectedRoutine)
                    appState.navigate(to: .onboardingRating)
                }
                .padding(.horizontal, onboardingButtonHorizontalPadding)
                .padding(.bottom, 32)
                .background(AppTheme.shared.current.colors.bgPrimary)
            }
        }
    }
}

struct OnboardingTransitionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.shared.current.colors.accent.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.5 : 0.8)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)

                Circle()
                    .fill(AppTheme.shared.current.colors.accent.opacity(0.4))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.2 : 0.6)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.4), value: isAnimating)

                Image(systemName: "faceid")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 20, x: 0, y: 0)
            }

            Text("Setting up your Skin Profile" + String(repeating: ".", count: dotCount))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 4
                }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            isAnimating = true
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let success = UINotificationFeedbackGenerator()
                success.notificationOccurred(.success)
                Task {
                    await appState.completeOnboardingFromDraft()
                }
            }
        }
    }
}

// MARK: - Rating Step

struct OnboardingRatingView: View {
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject var appState: AppState
    @State private var selectedStars: Int = 0
    @State private var hoverStar: Int = 0
    @State private var contentOpacity: Double = 0
    @State private var slideOffset: CGFloat = 30
    @State private var starScales: [CGFloat] = [1, 1, 1, 1, 1]
    @State private var showThankYou: Bool = false
    @State private var thankYouScale: CGFloat = 0.5
    @State private var thankYouOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            Circle()
                .fill(AppTheme.shared.current.colors.accentSoft)
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: 160, y: -200)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ProgressBar(currentStep: 6, totalSteps: 6)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                Spacer()

                // Main content — centred
                VStack(spacing: 32) {

                    // Icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.shared.current.colors.accent.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: "star.bubble.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    }
                    .opacity(contentOpacity)
                    .scaleEffect(contentOpacity)

                    // Headline
                    VStack(spacing: 10) {
                        Text("Give us 5 stars?")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("We built this for you. A quick rating takes 3 seconds and helps us reach more people who want better skin.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }
                    .opacity(contentOpacity)
                    .offset(y: slideOffset)

                    // Stars
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                let prev = selectedStars
                                selectedStars = star
                                // Ripple animation forward through the tapped stars
                                for i in 0..<5 {
                                    let delay = Double(i) * 0.06
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                                            starScales[i] = i < star ? 1.25 : 1.0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                starScales[i] = i < star ? 1.05 : 1.0
                                            }
                                        }
                                    }
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                // If 4 or 5 stars, also trigger the native App Store sheet (deferred slightly)
                                if star >= 4 && prev < 4 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        requestReview()
                                    }
                                }
                            } label: {
                                Image(systemName: selectedStars >= star ? "star.fill" : "star")
                                    .font(.system(size: 44, weight: .medium))
                                    .foregroundStyle(selectedStars >= star
                                        ? AppTheme.shared.current.colors.primaryGradient
                                        : LinearGradient(colors: [AppTheme.shared.current.colors.surfaceHigh],
                                                        startPoint: .top, endPoint: .bottom))
                                    .shadow(color: selectedStars >= star
                                        ? AppTheme.shared.current.colors.accentGlow
                                        : .clear, radius: 8)
                                    .scaleEffect(starScales[star - 1])
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .opacity(contentOpacity)

                    // Dynamic label
                    if selectedStars > 0 {
                        Text(ratingLabel(for: selectedStars))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.shared.current.colors.accent)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                contentOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6)) {
                slideOffset = 0
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton(selectedStars == 0 ? "Rate Skin Score" : "Continue",
                              isEnabled: true) {
                    appState.navigate(to: .onboardingTransition)
                }
                if selectedStars == 0 {
                    Button {
                        appState.navigate(to: .onboardingTransition)
                    } label: {
                        Text("Maybe later")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.shared.current.colors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 8)
            .background(AppTheme.shared.current.colors.bgPrimary)
        }
    }

    private func ratingLabel(for stars: Int) -> String {
        switch stars {
        case 1: return "Sorry to hear that. We'll keep improving."
        case 2: return "Thanks for the feedback. We'll do better."
        case 3: return "Good start. Lots more coming."
        case 4: return "Amazing. Thanks so much."
        case 5: return "You're the best. Thank you."
        default: return ""
        }
    }
}
