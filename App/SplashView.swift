import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppTheme.shared.current.colors.bgPrimary.ignoresSafeArea()
            
            VStack {
                Text(AppConfig.appName)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundColor(AppTheme.shared.current.colors.textPrimary)
                
                Text(AppConfig.tagline)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.shared.current.colors.textSecondary)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    SplashView()
}
