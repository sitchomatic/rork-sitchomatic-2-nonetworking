import SwiftUI

struct NeonProgressBar: View {
    let progress: Double
    let segments: [ProgressSegment]
    let height: CGFloat

    init(progress: Double, segments: [ProgressSegment] = [], height: CGFloat = 6) {
        self.progress = progress
        self.segments = segments.isEmpty ? [ProgressSegment(fraction: 1.0, color: NeonTheme.neonGreen)] : segments
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.06))

                let totalWidth = geo.size.width * min(progress, 1.0)
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: height / 2)
                            .fill(segment.color)
                            .frame(width: max(0, totalWidth * segment.fraction))
                    }
                }
                .frame(width: totalWidth, alignment: .leading)
                .clipShape(.rect(cornerRadius: height / 2))
                .neonGlow(segments.first?.color ?? NeonTheme.neonGreen, radius: 3)
            }
        }
        .frame(height: height)
    }
}

struct ProgressSegment {
    let fraction: CGFloat
    let color: Color
}
