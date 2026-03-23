import SwiftUI
import UIKit

struct SessionProofSheet: View {
    let session: ConcurrentSession
    @State private var showFullTimeline: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionHeader
                    screenshotProofSection
                    if let result = session.dualResult {
                        dualResultBreakdown(result)
                    }
                    if let error = session.errorMessage {
                        errorCard(error)
                    }
                    actionBar
                    enhancedTimeline
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(NeonTheme.surfaceBackground)
            .navigationTitle("Session Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeonTheme.surfaceBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if let result = session.dualResult {
                    Image(systemName: result.outcome.iconName)
                        .font(.system(size: 26))
                        .foregroundStyle(NeonTheme.outcomeColor(result.outcome))
                        .neonGlow(NeonTheme.outcomeColor(result.outcome), radius: 4)
                } else {
                    Image(systemName: session.phase.iconName)
                        .font(.system(size: 26))
                        .foregroundStyle(NeonTheme.phaseColor(session.phase))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.credential.username)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeonTheme.textPrimary)
                        if session.isFlaggedForReview {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(NeonTheme.neonYellow)
                        }
                    }
                    Text(session.credential.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(NeonTheme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let result = session.dualResult {
                        Text(result.outcome.shortName.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(NeonTheme.outcomeColor(result.outcome))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NeonTheme.outcomeColor(result.outcome).opacity(0.1), in: .capsule)
                    } else {
                        Text(session.phase.displayName.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(NeonTheme.phaseColor(session.phase))
                    }
                    Text(session.elapsedFormatted)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
            }

            HStack(spacing: 12) {
                metaChip(icon: "network", text: session.proxyInfo)
                metaChip(icon: "square.stack.3d.up", text: "Wave \(session.waveIndex + 1)")
                if session.retryCount > 0 {
                    metaChip(icon: "arrow.clockwise", text: "\(session.retryCount) retries")
                }
            }

            if session.totalSteps > 0 {
                VStack(spacing: 4) {
                    NeonProgressBar(progress: session.progress, height: 3)
                    Text("\(session.stepsCompleted)/\(session.totalSteps) steps")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
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

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(NeonTheme.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: .capsule)
    }

    // MARK: - Screenshots

    private var screenshotProofSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 11))
                    .foregroundStyle(NeonTheme.neonCyan)
                Text("PROOF SCREENSHOTS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }

            HStack(spacing: 8) {
                proofCard(
                    title: "Joe Fortune",
                    data: session.joeScreenshot,
                    outcome: session.dualResult?.joeOutcome
                )
                proofCard(
                    title: "Ignition Casino",
                    data: session.ignitionScreenshot,
                    outcome: session.dualResult?.ignitionOutcome
                )
            }
        }
    }

    private func proofCard(title: String, data: Data?, outcome: DualLoginOutcome?) -> some View {
        VStack(spacing: 0) {
            if let data, let uiImage = UIImage(data: data) {
                Color(white: 0.08)
                    .frame(height: 150)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
            } else {
                Color(white: 0.06)
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18))
                            Text("Awaiting Proof")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(NeonTheme.textTertiary)
                    }
                    .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
            }

            HStack(spacing: 4) {
                if let outcome {
                    Circle()
                        .fill(NeonTheme.outcomeColor(outcome))
                        .frame(width: 5, height: 5)
                }
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                if let outcome {
                    Text(outcome.shortName)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.outcomeColor(outcome))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(NeonTheme.cardBackground)
            .clipShape(.rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Result Breakdown

    private func dualResultBreakdown(_ result: DualLoginResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(NeonTheme.neonCyan)
                Text("RESULT BREAKDOWN")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }

            VStack(spacing: 6) {
                resultRow("Combined", value: result.outcome.longName, icon: result.outcome.iconName, color: NeonTheme.outcomeColor(result.outcome))
                resultRow("Joe Fortune", value: result.joeOutcome.longName, icon: result.joeOutcome.iconName, color: NeonTheme.outcomeColor(result.joeOutcome))
                resultRow("Ignition", value: result.ignitionOutcome.longName, icon: result.ignitionOutcome.iconName, color: NeonTheme.outcomeColor(result.ignitionOutcome))
                resultRow("Duration", value: String(format: "%.2fs", result.duration), icon: "clock", color: NeonTheme.textSecondary)
                resultRow("Proxy", value: result.proxyUsed, icon: "network", color: NeonTheme.textSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeonTheme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
            )
        }
    }

    private func resultRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NeonTheme.textTertiary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Error

    private func errorCard(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NeonTheme.neonRed)
            Text(error)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NeonTheme.neonRed)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeonTheme.neonRed.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.neonRed.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            if session.phase == .failed {
                neonActionButton(title: "Retry", icon: "arrow.clockwise", color: NeonTheme.neonOrange) {
                    ConcurrentAutomationEngine.shared.enqueueRetry(session.credential)
                }
            }

            neonActionButton(title: "Copy", icon: "doc.on.doc", color: NeonTheme.neonCyan) {
                UIPasteboard.general.string = session.credential.username
            }

            neonActionButton(
                title: session.isFlaggedForReview ? "Unflag" : "Flag",
                icon: session.isFlaggedForReview ? "flag.slash.fill" : "flag.fill",
                color: NeonTheme.neonYellow
            ) {
                session.toggleFlagged()
            }

            Spacer()
        }
    }

    private func neonActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.08), in: .capsule)
            .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeline

    private var enhancedTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.neonCyan)
                    Text("TIMELINE (\(session.logEntries.count))")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                Spacer()
                if !session.logEntries.isEmpty {
                    Button {
                        showFullTimeline = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8))
                            Text("Full Timeline")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(NeonTheme.neonCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NeonTheme.neonCyan.opacity(0.08), in: .capsule)
                        .overlay(Capsule().stroke(NeonTheme.neonCyan.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if session.logEntries.isEmpty {
                Text("No log entries recorded")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.logEntries.prefix(20).enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(NeonTheme.logCategoryColor(entry.category))
                                    .frame(width: 8, height: 8)
                                    .neonGlow(NeonTheme.logCategoryColor(entry.category), radius: 2)
                                if index < min(session.logEntries.count, 20) - 1 {
                                    Rectangle()
                                        .fill(NeonTheme.logCategoryColor(entry.category).opacity(0.15))
                                        .frame(width: 1.5)
                                        .frame(minHeight: 20)
                                }
                            }
                            .frame(width: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.category.rawValue.uppercased())
                                        .font(.system(size: 7, weight: .black, design: .monospaced))
                                        .foregroundStyle(NeonTheme.logCategoryColor(entry.category))
                                    Text(timeOnly(entry.timestamp))
                                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                                        .foregroundStyle(NeonTheme.textDim)
                                    if index > 0 {
                                        let delta = entry.timestamp.timeIntervalSince(session.logEntries[index - 1].timestamp)
                                        Text("+\(String(format: "%.1f", delta))s")
                                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(NeonTheme.textTertiary)
                                    }
                                }
                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(NeonTheme.textPrimary)
                                    .lineLimit(2)
                            }
                            .padding(.bottom, 6)
                        }
                    }

                    if session.logEntries.count > 20 {
                        Button {
                            showFullTimeline = true
                        } label: {
                            Text("\(session.logEntries.count - 20) more entries...")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NeonTheme.neonCyan)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NeonTheme.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                )
            }
        }
        .fullScreenCover(isPresented: $showFullTimeline) {
            FullTimelineView(session: session)
        }
    }

    private func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
