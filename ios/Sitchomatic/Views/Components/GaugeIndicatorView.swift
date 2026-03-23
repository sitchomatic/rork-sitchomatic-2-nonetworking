import SwiftUI

struct GaugeIndicatorView: View {
    let value: Double
    let maxValue: Double
    let label: String
    let count: String
    let color: Color

    private var normalizedValue: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.06), lineWidth: 3)
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * normalizedValue)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))

                Text(count)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .frame(width: 44, height: 44)

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textSecondary)
                .lineLimit(1)
        }
    }
}
