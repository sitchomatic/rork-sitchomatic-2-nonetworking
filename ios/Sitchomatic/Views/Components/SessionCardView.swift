import SwiftUI
import UIKit

struct SessionCardView: View {
    let session: ConcurrentSession
    let onTap: () -> Void
    let onRetry: () -> Void
    let onCopy: () -> Void
    let onFlag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            dualFeedPanels
                .padding(.horizontal, 14)

            progressSection
                .padding(.horizontal, 14)
                .padding(.top, 10)

            liveStatusCaption
                .padding(.horizontal, 14)
                .padding(.top, 8)

            footerMetrics
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)

            if session.phase.isTerminal {
                actionButtons
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor.opacity(0.15), lineWidth: 0.5)
                )
        )
        .onTapGesture { onTap() }
    }

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.credential.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NeonTheme.textPrimary)
                        .lineLimit(1)
                    if session.isFlaggedForReview {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(NeonTheme.neonYellow)
                    }
                }
                if let result = session.dualResult {
                    Text(result.outcome.longName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeonTheme.outcomeColor(result.outcome))
                }
            }

            Spacer()

            Menu {
                Button { onCopy() } label: {
                    Label("Copy Credential", systemImage: "doc.on.doc")
                }
                Button { onFlag() } label: {
                    Label(session.isFlaggedForReview ? "Unflag" : "Flag for Review", systemImage: session.isFlaggedForReview ? "flag.slash" : "flag")
                }
                if session.phase == .failed {
                    Button { onRetry() } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var dualFeedPanels: some View {
        HStack(spacing: 8) {
            sitePanel(
                title: "Joe",
                titleFont: .system(size: 20, weight: .bold),
                screenshotData: session.joeScreenshot,
                outcome: session.dualResult?.joeOutcome,
                bgColor: Color(red: 0.12, green: 0.12, blue: 0.12)
            )
            sitePanel(
                title: "Ignition",
                titleFont: .system(size: 16, weight: .bold),
                screenshotData: session.ignitionScreenshot,
                outcome: session.dualResult?.ignitionOutcome,
                bgColor: Color(red: 0.08, green: 0.12, blue: 0.22),
                isIgnition: true
            )
        }
    }

    private func sitePanel(title: String, titleFont: Font, screenshotData: Data?, outcome: DualLoginOutcome?, bgColor: Color, isIgnition: Bool = false) -> some View {
        VStack(spacing: 0) {
            if let data = screenshotData, let uiImage = UIImage(data: data) {
                Color.clear
                    .frame(height: 80)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        panelLabel(title: title, outcome: outcome, isIgnition: isIgnition)
                            .padding(6)
                    }
            } else {
                ZStack {
                    bgColor

                    VStack(spacing: 6) {
                        if isIgnition {
                            HStack(spacing: 2) {
                                Text("Ignition")
                                    .font(.system(size: 16, weight: .bold))
                                Text("✓")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(NeonTheme.neonOrange)
                            }
                            .foregroundStyle(NeonTheme.textPrimary)
                        } else {
                            Text(title)
                                .font(titleFont)
                                .foregroundStyle(NeonTheme.textPrimary)
                        }

                        if let outcome {
                            Text(outcome.shortName)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeonTheme.outcomeColor(outcome))
                        } else {
                            Text(session.phase.displayName)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(NeonTheme.textTertiary)
                        }
                    }
                }
                .frame(height: 80)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func panelLabel(title: String, outcome: DualLoginOutcome?, isIgnition: Bool) -> some View {
        HStack(spacing: 3) {
            if let outcome {
                Circle()
                    .fill(NeonTheme.outcomeColor(outcome))
                    .frame(width: 5, height: 5)
            }
            if isIgnition {
                HStack(spacing: 1) {
                    Text("Ign")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                    Text("✓")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(NeonTheme.neonOrange)
                }
                .foregroundStyle(.white)
            } else {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.7), in: .capsule)
    }

    private var progressSection: some View {
        NeonProgressBar(
            progress: session.phase.isTerminal ? 1.0 : max(session.progress, 0.05),
            segments: progressSegments,
            height: 5
        )
    }

    private var progressSegments: [ProgressSegment] {
        if let result = session.dualResult {
            switch result.outcome {
            case .success:
                return [ProgressSegment(fraction: 1.0, color: NeonTheme.neonGreen)]
            case .noAccount:
                return [
                    ProgressSegment(fraction: 0.7, color: NeonTheme.neonGreen),
                    ProgressSegment(fraction: 0.3, color: NeonTheme.neonIndigo)
                ]
            case .permDisabled:
                return [
                    ProgressSegment(fraction: 0.5, color: NeonTheme.neonGreen),
                    ProgressSegment(fraction: 0.5, color: NeonTheme.neonRed)
                ]
            case .tempDisabled:
                return [
                    ProgressSegment(fraction: 0.6, color: NeonTheme.neonGreen),
                    ProgressSegment(fraction: 0.4, color: NeonTheme.neonOrange)
                ]
            case .unsure:
                return [
                    ProgressSegment(fraction: 0.6, color: NeonTheme.neonGreen),
                    ProgressSegment(fraction: 0.2, color: NeonTheme.neonCyan),
                    ProgressSegment(fraction: 0.2, color: NeonTheme.neonMagenta)
                ]
            case .error:
                return [
                    ProgressSegment(fraction: 0.4, color: NeonTheme.neonGreen),
                    ProgressSegment(fraction: 0.6, color: NeonTheme.neonYellow)
                ]
            }
        }

        if session.phase.isActive {
            return [
                ProgressSegment(fraction: 0.8, color: NeonTheme.neonGreen),
                ProgressSegment(fraction: 0.2, color: NeonTheme.neonCyan)
            ]
        }

        return [ProgressSegment(fraction: 1.0, color: NeonTheme.neonGreen)]
    }

    private var liveStatusCaption: some View {
        HStack(spacing: 0) {
            Text("Live status: ")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeonTheme.textTertiary)
            Text(statusMessage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
    }

    private var statusMessage: String {
        if let result = session.dualResult {
            return "\(result.outcome.longName) — \(String(format: "%.1f", result.duration))s"
        }
        if let error = session.errorMessage {
            return error
        }
        switch session.phase {
        case .queued: return "Queued for processing"
        case .launching: return "Launching session pair..."
        case .navigating: return "Navigating to login page..."
        case .running: return "Session check for [\(session.credential.username)] underway"
        case .waitingForElement: return "Waiting for page elements..."
        case .fillingForm: return "Parsing details for [Session ID: \(String(session.id.uuidString.prefix(4)).uppercased())]"
        case .asserting: return "Verifying login result..."
        case .screenshotting: return "Capturing proof screenshot..."
        case .succeeded: return "Session completed successfully"
        case .failed: return "Session failed"
        case .cancelled: return "Session cancelled"
        }
    }

    private var statusColor: Color {
        if session.dualResult != nil {
            return NeonTheme.outcomeColor(session.dualResult?.outcome)
        }
        if session.errorMessage != nil { return NeonTheme.neonRed }
        if session.phase.isActive { return NeonTheme.neonGreen }
        return NeonTheme.textSecondary
    }

    private var footerMetrics: some View {
        HStack {
            if let result = session.dualResult {
                HStack(spacing: 4) {
                    outcomeDot(result.joeOutcome)
                    Text("Joe: \(result.joeOutcome.shortName)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                HStack(spacing: 4) {
                    outcomeDot(result.ignitionOutcome)
                    Text("Ign: \(result.ignitionOutcome.shortName)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
            }
            Spacer()
            Text("Conn: 1")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)
            Text("Sys: 1")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)
        }
    }

    private func outcomeDot(_ outcome: DualLoginOutcome) -> some View {
        Circle()
            .fill(NeonTheme.outcomeColor(outcome))
            .frame(width: 5, height: 5)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if session.phase == .failed {
                Button { onRetry() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(NeonTheme.neonOrange)
                .controlSize(.mini)
            }

            Button { onCopy() } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(NeonTheme.neonCyan)
            .controlSize(.mini)

            Button { onFlag() } label: {
                Label(
                    session.isFlaggedForReview ? "Unflag" : "Flag",
                    systemImage: session.isFlaggedForReview ? "flag.slash.fill" : "flag.fill"
                )
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(NeonTheme.neonYellow)
            .controlSize(.mini)

            Spacer()
        }
    }

    private var cardBorderColor: Color {
        if let result = session.dualResult {
            return NeonTheme.outcomeColor(result.outcome)
        }
        if session.phase.isActive { return NeonTheme.neonGreen }
        return NeonTheme.cardBorder
    }
}
