import SwiftUI
import UIKit

struct FullTimelineView: View {
    let session: ConcurrentSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    timelineHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    if session.logEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 28))
                                .foregroundStyle(NeonTheme.textTertiary)
                            Text("No Timeline")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(NeonTheme.textSecondary)
                            Text("This session has no recorded log entries yet.")
                                .font(.system(size: 11))
                                .foregroundStyle(NeonTheme.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(session.logEntries.enumerated()), id: \.element.id) { index, entry in
                                timelineNode(entry: entry, index: index, isLast: index == session.logEntries.count - 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(NeonTheme.trueBlack)
            .navigationTitle("Full Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeonTheme.neonCyan)
                }
            }
        }
    }

    // MARK: - Header

    private var timelineHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if let result = session.dualResult {
                    Image(systemName: result.outcome.iconName)
                        .font(.title2)
                        .foregroundStyle(NeonTheme.outcomeColor(result.outcome))
                        .neonGlow(NeonTheme.outcomeColor(result.outcome), radius: 4)
                } else {
                    Image(systemName: session.phase.iconName)
                        .font(.title2)
                        .foregroundStyle(NeonTheme.neonCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.credential.username)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textPrimary)
                    Text("\(session.logEntries.count) events \u{2022} \(session.elapsedFormatted)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                }

                Spacer()

                if let result = session.dualResult {
                    Text(result.outcome.longName)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.outcomeColor(result.outcome))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NeonTheme.outcomeColor(result.outcome).opacity(0.1), in: .capsule)
                }
            }

            if session.joeScreenshot != nil || session.ignitionScreenshot != nil {
                HStack(spacing: 8) {
                    timelineScreenshot(label: "JOE", data: session.joeScreenshot, outcome: session.dualResult?.joeOutcome)
                    timelineScreenshot(label: "IGN", data: session.ignitionScreenshot, outcome: session.dualResult?.ignitionOutcome)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private func timelineScreenshot(label: String, data: Data?, outcome: DualLoginOutcome?) -> some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Color(white: 0.08)
                    .frame(height: 90)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 4) {
                            if let outcome {
                                Circle()
                                    .fill(NeonTheme.outcomeColor(outcome))
                                    .frame(width: 4, height: 4)
                            }
                            Text(label)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: .capsule)
                        .padding(6)
                    }
            } else {
                Color(white: 0.06)
                    .frame(height: 90)
                    .overlay {
                        Text(label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(NeonTheme.textDim)
                    }
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline Nodes

    private func timelineNode(entry: SessionLogLine, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(NeonTheme.logCategoryColor(entry.category))
                        .frame(width: 12, height: 12)
                        .neonGlow(NeonTheme.logCategoryColor(entry.category), radius: 3)
                    Circle()
                        .fill(NeonTheme.trueBlack)
                        .frame(width: 4, height: 4)
                }

                if !isLast {
                    Rectangle()
                        .fill(NeonTheme.logCategoryColor(entry.category).opacity(0.15))
                        .frame(width: 1.5)
                        .frame(minHeight: 36)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(categoryLabel(entry.category))
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.logCategoryColor(entry.category))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NeonTheme.logCategoryColor(entry.category).opacity(0.1), in: .capsule)

                    Text(timeString(entry.timestamp))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeonTheme.textDim)

                    if index > 0 {
                        let delta = entry.timestamp.timeIntervalSince(session.logEntries[index - 1].timestamp)
                        Text("+\(String(format: "%.1f", delta))s")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NeonTheme.textTertiary)
                    }
                }

                Text(entry.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if entry.category == .result, let result = session.dualResult {
                    HStack(spacing: 10) {
                        resultBadge("Joe", outcome: result.joeOutcome)
                        resultBadge("Ign", outcome: result.ignitionOutcome)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }

    private func resultBadge(_ label: String, outcome: DualLoginOutcome) -> some View {
        HStack(spacing: 4) {
            Image(systemName: outcome.iconName)
                .font(.system(size: 7))
                .foregroundStyle(NeonTheme.outcomeColor(outcome))
            Text("\(label): \(outcome.shortName)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeonTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NeonTheme.outcomeColor(outcome).opacity(0.06), in: .capsule)
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        return f.string(from: date)
    }

    private func categoryLabel(_ cat: SessionLogLine.Category) -> String {
        switch cat {
        case .phase: "PHASE"
        case .action: "ACTION"
        case .network: "NET"
        case .error: "ERROR"
        case .result: "RESULT"
        }
    }
}
