import SwiftUI

public enum ThemeMode { case light, dark }

public protocol ThemeProviding {
    var colors: ColorTokens { get }
    var motion: MotionTokens { get }
}

public struct ColorTokens {
    public let bgPrimary: Color
    public let surface: Color
    public let surfaceHigh: Color
    
    public let accent: Color
    public let accentSoft: Color
    public let accentGlow: Color
    public let accentGradientStart: Color
    public let accentGradientEnd: Color
    
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    
    public let success: Color
    public let warning: Color
    public let error: Color
    public let scoreColor: Color
    
    public var primaryGradient: LinearGradient {
        LinearGradient(colors: [accentGradientStart, accentGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension ColorTokens {
    public static var pastel: ColorTokens {
        ColorTokens(
            bgPrimary: Color(lightHex: "#FDF9F9", darkHex: "#1C1818"),
            surface: Color(lightHex: "#FFFFFF", darkHex: "#272222"),
            surfaceHigh: Color(lightHex: "#FFF2F2", darkHex: "#332B2B"),
            accent: Color(lightHex: "#FF9A9E", darkHex: "#FFB6B9"),
            accentSoft: Color(lightHex: "#FF9A9E", darkHex: "#FFB6B9").opacity(0.15),
            accentGlow: Color(lightHex: "#FF9A9E", darkHex: "#FFB6B9").opacity(0.4),
            accentGradientStart: Color(lightHex: "#FF9A9E", darkHex: "#FFB6B9"),
            accentGradientEnd: Color(lightHex: "#FECFEF", darkHex: "#E2B0FF"),
            textPrimary: Color(lightHex: "#4A3B3B", darkHex: "#FCEEEF"),
            textSecondary: Color(lightHex: "#9A8B8B", darkHex: "#C0B2B2"),
            textTertiary: Color(lightHex: "#C4B5B5", darkHex: "#968A8A"),
            // Keep success semantics without introducing legacy green UI.
            success: Color(lightHex: "#FFC2CF", darkHex: "#FF9FB4"),
            warning: Color(lightHex: "#FFD3B6", darkHex: "#FFC299"),
            error: Color(lightHex: "#FFAAA5", darkHex: "#FF9892"),
            scoreColor: Color(lightHex: "#FFB7B2", darkHex: "#FF9E99")
        )
    }
    
    public static var purpleDark: ColorTokens {
        ColorTokens(
            bgPrimary: Color(lightHex: "#0D0A13", darkHex: "#0D0A13"), // Pure dark theme
            surface: Color(lightHex: "#1C1629", darkHex: "#1C1629"),
            surfaceHigh: Color(lightHex: "#281E3B", darkHex: "#281E3B"),
            accent: Color(lightHex: "#A872FF", darkHex: "#A872FF"),
            accentSoft: Color(lightHex: "#A872FF", darkHex: "#A872FF").opacity(0.15),
            accentGlow: Color(lightHex: "#A872FF", darkHex: "#A872FF").opacity(0.4),
            accentGradientStart: Color(lightHex: "#A872FF", darkHex: "#A872FF"),
            accentGradientEnd: Color(lightHex: "#FF7EB3", darkHex: "#FF7EB3"),
            textPrimary: Color(lightHex: "#F0EBF5", darkHex: "#F0EBF5"),
            textSecondary: Color(lightHex: "#B4A8C4", darkHex: "#B4A8C4"),
            textTertiary: Color(lightHex: "#8B7D9E", darkHex: "#8B7D9E"),
            success: Color(lightHex: "#E8A0FF", darkHex: "#E8A0FF"),
            warning: Color(lightHex: "#FFCA62", darkHex: "#FFCA62"),
            error: Color(lightHex: "#FF6E8D", darkHex: "#FF6E8D"),
            scoreColor: Color(lightHex: "#C7A6FF", darkHex: "#C7A6FF")
        )
    }
}

public struct MotionTokens {
    public let durationBase: Double = 0.2 // 200ms
    public let pressScale: CGFloat = 0.96
    public let countUpDuration: Double = 1.5
}

public struct DynamicTheme: ThemeProviding {
    public var colors: ColorTokens
    public var motion = MotionTokens()
    
    public init(themeName: String) {
        if themeName == "purple" {
            self.colors = .purpleDark
        } else {
            self.colors = .pastel
        }
    }
}

public struct AppTheme {
    public static let shared = AppTheme()
    
    // We now rely on dynamic colors natively, so this mode variable is just informational
    public var mode: ThemeMode = .light
    
    public var current: ThemeProviding {
        let themeName = UserDefaults.standard.string(forKey: "appTheme") ?? "pastel"
        return DynamicTheme(themeName: themeName)
    }
}

// Global Glassmorphism Modifier
struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderOpacity: Double
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.shared.current.colors.textPrimary.opacity(borderOpacity), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassmorphism(cornerRadius: CGFloat = 20, borderOpacity: Double = 0.15) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
    }
}
