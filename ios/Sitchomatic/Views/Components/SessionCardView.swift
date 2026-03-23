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

            dualSitePanels
                .padding(.horizontal, 14)

            if let result = session.dualResult {
                resultSummaryText(result)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            progressSection
                .padding(.horizontal, 14)
                .padding(.top, 10)

            liveStatusRow
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)

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

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
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

    // MARK: - Dual Site Panels

    private var dualSitePanels: some View {
        HStack(spacing: 8) {
            sitePanelCard(
                site: .joe,
                screenshotData: session.joeScreenshot,
                outcome: session.dualResult?.joeOutcome,
                trace: session.dualResult?.joeTrace ?? []
            )

            sitePanelCard(
                site: .ignition,
                screenshotData: session.ignitionScreenshot,
                outcome: session.dualResult?.ignitionOutcome,
                trace: session.dualResult?.ignitionTrace ?? []
            )
        }
    }

    private func sitePanelCard(site: AutomationSite, screenshotData: Data?, outcome: DualLoginOutcome?, trace: [TraceEntry]) -> some View {
        VStack(spacing: 0) {
            if let data = screenshotData, let uiImage = UIImage(data: data) {
                screenshotPanel(site: site, uiImage: uiImage, outcome: outcome, trace: trace)
            } else {
                placeholderPanel(site: site, outcome: outcome, trace: trace)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func screenshotPanel(site: AutomationSite, uiImage: UIImage, outcome: DualLoginOutcome?, trace: [TraceEntry]) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 120)
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    siteLabel(site: site, outcome: outcome)
                        .padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if let outcome {
                        outcomePill(outcome)
                            .padding(6)
                    }
                }
        }
    }

    private func placeholderPanel(site: AutomationSite, outcome: DualLoginOutcome?, trace: [TraceEntry]) -> some View {
        let bgColor: Color = site == .joe
            ? Color(red: 0.10, green: 0.10, blue: 0.12)
            : Color(red: 0.06, green: 0.10, blue: 0.20)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Spacer()
                siteTitle(site: site)
                Spacer()
            }

            if !trace.isEmpty {
                traceLines(trace: trace, site: site)
            } else if let outcome {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: outcome.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(NeonTheme.outcomeColor(outcome))
                        Text(outcome.shortName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeonTheme.outcomeColor(outcome))
                    }
                    Spacer()
                }
            } else {
                activePhaseLines(site: site)
            }

            if let outcome {
                HStack {
                    Spacer()
                    outcomePill(outcome)
                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(bgColor, in: .rect(cornerRadius: 10))
    }

    private func siteTitle(site: AutomationSite) -> some View {
        Group {
            if site == .ignition {
                HStack(spacing: 2) {
                    Text("Ignition")
                        .font(.system(size: 18, weight: .bold))
                    Text("\u{2713}")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NeonTheme.neonOrange)
                }
                .foregroundStyle(NeonTheme.textPrimary)
            } else {
                Text("Joe")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
            }
        }
    }

    private func siteLabel(site: AutomationSite, outcome: DualLoginOutcome?) -> some View {
        HStack(spacing: 3) {
            if let outcome {
                Circle()
                    .fill(NeonTheme.outcomeColor(outcome))
                    .frame(width: 5, height: 5)
            }
            if site == .ignition {
                HStack(spacing: 1) {
                    Text("Ign")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                    Text("\u{2713}")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(NeonTheme.neonOrange)
                }
                .foregroundStyle(.white)
            } else {
                Text("Joe")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.7), in: .capsule)
    }

    private func outcomePill(_ outcome: DualLoginOutcome) -> some View {
        Text(outcome.shortName)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(NeonTheme.outcomeColor(outcome))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(NeonTheme.outcomeColor(outcome).opacity(0.15), in: .capsule)
    }

    // MARK: - Trace Lines

    private func traceLines(trace: [TraceEntry], site: AutomationSite) -> some View {
        let displayEntries = trace.suffix(4)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(displayEntries)) { entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(traceColor(entry.category))
                        .frame(width: 4, height: 4)
                    Text(entry.message)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func traceColor(_ category: TraceCategory) -> Color {
        switch category {
        case .navigation: NeonTheme.neonCyan
        case .action: NeonTheme.neonGreen
        case .evaluate: NeonTheme.neonIndigo
        case .screenshot: NeonTheme.neonYellow
        case .wait: NeonTheme.neonOrange
        case .assertion: NeonTheme.neonPurple
        case .system: NeonTheme.textTertiary
        }
    }

    private func activePhaseLines(site: AutomationSite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch session.phase {
            case .queued:
                phaseDetailLine("Waiting in queue...", color: NeonTheme.textTertiary)
            case .launching:
                phaseDetailLine("Launching browser...", color: NeonTheme.neonCyan)
            case .navigating:
                phaseDetailLine("Loading login page...", color: NeonTheme.neonCyan)
                phaseDetailLine(site.defaultLoginURL.prefix(30) + "...", color: NeonTheme.textTertiary)
            case .running:
                phaseDetailLine("Session active", color: NeonTheme.neonGreen)
                phaseDetailLine("Attempt in progress...", color: NeonTheme.textTertiary)
            case .waitingForElement:
                phaseDetailLine("Waiting for elements...", color: NeonTheme.neonOrange)
                phaseDetailLine("JS settlement check", color: NeonTheme.textTertiary)
            case .fillingForm:
                phaseDetailLine("Filling credentials...", color: NeonTheme.neonCyan)
                phaseDetailLine(session.credential.username.prefix(20) + "...", color: NeonTheme.textTertiary)
            case .asserting:
                phaseDetailLine("Checking response...", color: NeonTheme.neonPurple)
                phaseDetailLine("Button color revert wait", color: NeonTheme.textTertiary)
            case .screenshotting:
                phaseDetailLine("Capturing proof...", color: NeonTheme.neonGreen)
            default:
                phaseDetailLine(session.phase.displayName, color: NeonTheme.textTertiary)
            }
        }
    }

    private func phaseDetailLine(_ text: any StringProtocol, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Result Summary

    private func resultSummaryText(_ result: DualLoginResult) -> some View {
        Text(resultDescription(result))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NeonTheme.textSecondary)
            .lineLimit(2)
    }

    private func resultDescription(_ result: DualLoginResult) -> String {
        switch result.outcome {
        case .success:
            return "Successful login on \(siteHitText(result)). Session cookies saved."
        case .noAccount:
            return "4/4 attempts completed on both sites. All incorrect password — no account exists."
        case .permDisabled:
            return "Permanently disabled detected on \(permSiteText(result)). Early-stop applied."
        case .tempDisabled:
            return "Temporarily disabled on \(tempSiteText(result)) — account confirmed (wrong password)."
        case .unsure:
            return "Mixed results — Joe: \(result.joeOutcome.shortName), Ignition: \(result.ignitionOutcome.shortName). Manual review needed."
        case .error:
            return result.errorMessage ?? "Error during login attempt."
        }
    }

    private func siteHitText(_ result: DualLoginResult) -> String {
        var sites: [String] = []
        if result.joeOutcome == .success { sites.append("Joe") }
        if result.ignitionOutcome == .success { sites.append("Ignition") }
        return sites.isEmpty ? "site" : sites.joined(separator: " & ")
    }

    private func permSiteText(_ result: DualLoginResult) -> String {
        var sites: [String] = []
        if result.joeOutcome == .permDisabled { sites.append("Joe") }
        if result.ignitionOutcome == .permDisabled { sites.append("Ignition") }
        return sites.isEmpty ? "site" : sites.joined(separator: " & ")
    }

    private func tempSiteText(_ result: DualLoginResult) -> String {
        var sites: [String] = []
        if result.joeOutcome == .tempDisabled { sites.append("Joe") }
        if result.ignitionOutcome == .tempDisabled { sites.append("Ignition") }
        return sites.isEmpty ? "site" : sites.joined(separator: " & ")
    }

    // MARK: - Progress

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

    // MARK: - Live Status + Footer

    private var liveStatusRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Live status: ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NeonTheme.textTertiary)
                    Text(statusMessage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                if let result = session.dualResult {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            outcomeDot(result.joeOutcome)
                            Text("Joe: \(result.joeOutcome.shortName)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NeonTheme.textSecondary)
                        }
                        HStack(spacing: 3) {
                            outcomeDot(result.ignitionOutcome)
                            Text("Ign: \(result.ignitionOutcome.shortName)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NeonTheme.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("Conn: 1")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                Text("Syn: 1")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
            }
        }
    }

    private func outcomeDot(_ outcome: DualLoginOutcome) -> some View {
        Circle()
            .fill(NeonTheme.outcomeColor(outcome))
            .frame(width: 5, height: 5)
    }

    private var statusMessage: String {
        if let result = session.dualResult {
            return "\(result.outcome.longName) \u{2014} \(String(format: "%.1f", result.duration))s"
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

    // MARK: - Action Buttons

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

    // MARK: - Helpers

    private var cardBorderColor: Color {
        if let result = session.dualResult {
            return NeonTheme.outcomeColor(result.outcome)
        }
        if session.phase.isActive { return NeonTheme.neonGreen }
        return NeonTheme.cardBorder
    }
}
