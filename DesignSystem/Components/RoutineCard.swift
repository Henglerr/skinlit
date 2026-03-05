import SwiftUI

public struct RoutineCard: View {
    public let title: String
    public let symbolName: String?
    public let description: String
    public let isSelected: Bool
    public let action: () -> Void
    
    @State private var isPressed: Bool = false
    
    public init(title: String, symbolName: String? = nil, description: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.description = description
        self.isSelected = isSelected
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.surfaceHigh)
                        .frame(width: 28, height: 28)
                        .shadow(color: isSelected ? AppTheme.shared.current.colors.accentGlow : .clear, radius: 4)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let symbolName {
                            Image(systemName: symbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isSelected
                                    ? AppTheme.shared.current.colors.accent
                                    : AppTheme.shared.current.colors.textSecondary)
                        }

                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    }
                    
                    Text(description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isSelected ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isSelected {
                        AppTheme.shared.current.colors.accentSoft
                    } else {
                        AppTheme.shared.current.colors.surface
                    }
                }
            )
            .glassmorphism(cornerRadius: 24, borderOpacity: isSelected ? 0.5 : 0.1)
            .shadow(color: isSelected ? AppTheme.shared.current.colors.accentGlow.opacity(0.4) : .clear, radius: 20, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSelected ? AppTheme.shared.current.colors.accent : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? AppTheme.shared.current.motion.pressScale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents { pressed in
            isPressed = pressed
        }
    }
}
