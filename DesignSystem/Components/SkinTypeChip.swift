import SwiftUI

public struct SkinTypeChip: View {
    public let symbolName: String
    public let title: String
    public let description: String
    public let isSelected: Bool
    public let action: () -> Void
    
    @State private var isPressed: Bool = false
    
    public init(symbolName: String, title: String, description: String, isSelected: Bool, action: @escaping () -> Void) {
        self.symbolName = symbolName
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected
                            ? AppTheme.shared.current.colors.accent
                            : AppTheme.shared.current.colors.textSecondary)
                        .frame(width: 22, height: 22)

                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }

                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isSelected ? AppTheme.shared.current.colors.textPrimary : AppTheme.shared.current.colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.trailing, 44)
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
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
            .overlay(alignment: .topTrailing) {
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
                .padding(14)
            }
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
