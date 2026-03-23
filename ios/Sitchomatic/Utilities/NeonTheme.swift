import SwiftUI

enum NeonTheme {
    static let neonGreen = Color(red: 0, green: 1, blue: 0.4)
    static let neonCyan = Color(red: 0, green: 0.898, blue: 1)
    static let neonMagenta = Color(red: 1, green: 0, blue: 0.6)
    static let neonOrange = Color(red: 1, green: 0.6, blue: 0)
    static let neonRed = Color(red: 1, green: 0.2, blue: 0.2)
    static let neonYellow = Color(red: 1, green: 0.92, blue: 0.23)
    static let neonIndigo = Color(red: 0.45, green: 0.35, blue: 1)
    static let neonPurple = Color(red: 0.7, green: 0.3, blue: 1)

    static let cardBackground = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.08)
    static let surfaceBackground = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let trueBlack = Color.black

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)
    static let textDim = Color.white.opacity(0.2)

    static func outcomeColor(_ outcome: DualLoginOutcome?) -> Color {
        guard let outcome else { return .gray }
        switch outcome {
        case .success: return neonGreen
        case .noAccount: return neonIndigo
        case .permDisabled: return neonRed
        case .tempDisabled: return neonOrange
        case .unsure: return neonPurple
        case .error: return neonYellow
        }
    }

    static func phaseColor(_ phase: SessionPhase) -> Color {
        switch phase {
        case .succeeded: neonGreen
        case .failed: neonRed
        case .cancelled: .gray
        case .queued: textTertiary
        default: neonCyan
        }
    }

    static func healthColor(_ score: Double) -> Color {
        if score > 0.7 { return neonGreen }
        if score > 0.4 { return neonOrange }
        return neonRed
    }

    static func memoryColor(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .safe: neonGreen
        case .elevated: neonYellow
        case .critical: neonOrange
        case .emergency: neonRed
        }
    }

    static func logCategoryColor(_ cat: SessionLogLine.Category) -> Color {
        switch cat {
        case .phase: neonPurple
        case .action: neonCyan
        case .network: Color(red: 0.3, green: 0.5, blue: 1)
        case .error: neonRed
        case .result: neonGreen
        }
    }
}

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(NeonTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                    )
            )
    }
}

struct NeonGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func neonGlow(_ color: Color, radius: CGFloat = 4) -> some View {
        modifier(NeonGlow(color: color, radius: radius))
    }
}
