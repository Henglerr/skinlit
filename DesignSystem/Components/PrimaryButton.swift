import SwiftUI

public struct PrimaryButton: View {
    public let title: String
    public let action: () -> Void
    public var icon: String? = nil
    public var isEnabled: Bool = true
    
    @State private var isPressed: Bool = false
    
    public init(_ title: String, icon: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Group {
                    if isEnabled {
                        AppTheme.shared.current.colors.primaryGradient
                    } else {
                        AppTheme.shared.current.colors.surfaceHigh.opacity(0.5)
                    }
                }
            )
            .foregroundColor(isEnabled ? AppTheme.shared.current.colors.bgPrimary : AppTheme.shared.current.colors.textSecondary)
            .cornerRadius(20)
            .shadow(
                color: isEnabled ? AppTheme.shared.current.colors.accentGlow : Color.clear,
                radius: 12, x: 0, y: 4
            )
            .scaleEffect(isPressed && isEnabled ? AppTheme.shared.current.motion.pressScale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .disabled(!isEnabled)
        .pressEvents { pressed in
            isPressed = pressed
        }
    }
}

// Helper to detect press state on gestures without breaking Button interactions
extension View {
    func pressEvents(onPress: @escaping (Bool) -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded { _ in onPress(false) }
        )
    }
}
