import SwiftUI

struct HealthRingView: View {
    let progress: Double
    let label: String
    let stateLabel: String
    let size: CGFloat

    private var ringColor: Color {
        NeonTheme.healthColor(progress)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: size * 0.06)

            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .neonGlow(ringColor, radius: 6)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: size * 0.22, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)

                Text(stateLabel)
                    .font(.system(size: size * 0.1, weight: .semibold))
                    .foregroundStyle(ringColor)
            }
        }
        .frame(width: size, height: size)
    }
}
