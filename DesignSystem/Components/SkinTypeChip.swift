import SwiftUI

public struct SkinTypeChip: View {
    public let icon: String
    public let title: String
    public let description: String
    public let isSelected: Bool
    public let action: () -> Void
    
    @State private var isPressed: Bool = false
    
    public init(icon: String, title: String, description: String, isSelected: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(icon)
                        .font(.system(size: 28))
                        .shadow(color: isSelected ? AppTheme.shared.current.colors.accentGlow : .clear, radius: 8)
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppTheme.shared.current.colors.accent : AppTheme.shared.current.colors.surfaceHigh)
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                    
                    Text(description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isSelected ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
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
            .glassmorphism(cornerRadius: 20, borderOpacity: isSelected ? 0.5 : 0.1)
            .shadow(color: isSelected ? AppTheme.shared.current.colors.accentGlow.opacity(0.5) : .clear, radius: 15, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppTheme.shared.current.colors.accent : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? AppTheme.shared.current.motion.pressScale : (isSelected ? 1.02 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents { pressed in
            isPressed = pressed
        }
    }
}
