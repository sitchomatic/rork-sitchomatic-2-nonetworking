import SwiftUI

struct WaveformView: View {
    let barCount: Int
    let color: Color
    @State private var animationPhase: Double = 0

    init(barCount: Int = 40, color: Color = NeonTheme.neonGreen) {
        self.barCount = barCount
        self.color = color
    }

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                let normalizedHeight = waveHeight(for: index)
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.4 + normalizedHeight * 0.6))
                    .frame(width: 2, height: max(2, normalizedHeight * 32))
            }
        }
        .frame(height: 36)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }

    private func waveHeight(for index: Int) -> Double {
        let x = Double(index) / Double(barCount)
        let wave1 = sin(x * .pi * 4 + animationPhase) * 0.3
        let wave2 = sin(x * .pi * 7 + animationPhase * 1.3) * 0.2
        let wave3 = sin(x * .pi * 2 + animationPhase * 0.7) * 0.4
        let envelope = sin(x * .pi) * 0.8 + 0.2
        return max(0.08, (wave1 + wave2 + wave3 + 0.5) * envelope)
    }
}
