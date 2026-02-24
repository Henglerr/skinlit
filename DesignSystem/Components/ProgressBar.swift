import SwiftUI

public struct ProgressBar: View {
    public let currentStep: Int
    public let totalSteps: Int
    
    public init(currentStep: Int, totalSteps: Int) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .frame(width: geometry.size.width, height: 8)
                    .foregroundColor(AppTheme.shared.current.colors.surfaceHigh)
                    .cornerRadius(4)
                
                // Progress Fill
                Rectangle()
                    .frame(width: max(0, min(CGFloat(currentStep) / CGFloat(totalSteps), 1.0)) * geometry.size.width, height: 8)
                    .foregroundStyle(AppTheme.shared.current.colors.primaryGradient)
                    .cornerRadius(4)
                    .shadow(color: AppTheme.shared.current.colors.accentGlow, radius: 4, x: 0, y: 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
            }
        }
        .frame(height: 8)
    }
}
