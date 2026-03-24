import SwiftUI
import UIKit

struct LiveTestsFeedView: View {
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var selectedSession: ConcurrentSession?
    @State private var sessionFilter: SessionVisibilityFilter = .all
    @State private var showsCompletedOnly: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            stickyHeader
            filterBar
                .padding(.top, 8)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredSessions.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    } else {
                        ForEach(filteredSessions) { session in
                            LiveTestCard(session: session) {
                                selectedSession = session
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Live Tests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedSession) { session in
            SessionProofSheet(session: session)
        }
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairs Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeonTheme.textTertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(processedCount)")
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeonTheme.neonGreen)
                            .neonGlow(NeonTheme.neonGreen, radius: 4)
                            .contentTransition(.numericText())
                        Text("/\(engine.sessions.count)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NeonTheme.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.isRunning ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                            .frame(width: 6, height: 6)
                            .neonGlow(engine.isRunning ? NeonTheme.neonGreen : .clear, radius: 3)
                        Text(engine.isRunning ? "Processing" : "Processed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(engine.isRunning ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 12) {
                        miniStat(value: "\(engine.succeededCount)", label: "Hit", color: NeonTheme.neonGreen)
                        miniStat(value: "\(engine.activeCount)", label: "Live", color: NeonTheme.neonCyan)
                        miniStat(value: "\(engine.failedCount)", label: "Fail", color: NeonTheme.neonRed)
                    }

                    if engine.totalPasswordPhases > 1 {
                        Text(engine.passwordPhaseLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeonTheme.neonCyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(NeonTheme.neonCyan.opacity(0.1), in: .capsule)
                    }
                }
            }

            NeonProgressBar(
                progress: engine.sessions.isEmpty ? 0 : engine.overallProgress,
                height: 5
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            NeonTheme.surfaceBackground
                .overlay(
                    Rectangle()
                        .fill(NeonTheme.neonGreen.opacity(engine.isRunning ? 0.03 : 0))
                )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NeonTheme.cardBorder)
                .frame(height: 0.5)
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionVisibilityFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            sessionFilter = filter
                        }
                    } label: {
                        let isSelected = sessionFilter == filter
                        HStack(spacing: 4) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 8))
                            Text(filter.title)
                            Text("\(count(for: filter))")
                                .foregroundStyle(isSelected ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? NeonTheme.neonGreen.opacity(0.12) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? NeonTheme.neonGreen.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sessionFilter == filter ? NeonTheme.neonGreen : NeonTheme.textSecondary)
                }
            }
        }
        .contentMargins(.horizontal, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 36))
                .foregroundStyle(NeonTheme.textTertiary)
            Text("No Tests Yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NeonTheme.textSecondary)
            Text("Start a Dual Run to see live session\ncards streaming in here.")
                .font(.system(size: 12))
                .foregroundStyle(NeonTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private var processedCount: Int {
        engine.sessions.filter { $0.phase.isTerminal }.count
    }

    private var filteredSessions: [ConcurrentSession] {
        let sessions: [ConcurrentSession]
        switch sessionFilter {
        case .all:
            sessions = engine.sessions
        case .active:
            sessions = engine.sessions.filter { $0.phase.isActive || $0.phase == .queued }
        case .success:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .success }
        case .noAccount:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .noAccount }
        case .permDisabled:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .permDisabled }
        case .tempDisabled:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .tempDisabled }
        case .unsure:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .unsure }
        case .error:
            sessions = engine.sessions.filter { $0.dualResult?.outcome == .error }
        }

        return sessions.sorted { lhs, rhs in
            if lhs.phase.isActive != rhs.phase.isActive {
                return lhs.phase.isActive
            }
            if lhs.phase == .queued && rhs.phase != .queued && !rhs.phase.isActive {
                return true
            }
            return lhs.index < rhs.index
        }
    }

    private func count(for filter: SessionVisibilityFilter) -> Int {
        switch filter {
        case .all: engine.sessions.count
        case .active: engine.sessions.filter { $0.phase.isActive || $0.phase == .queued }.count
        case .success: engine.sessions.filter { $0.dualResult?.outcome == .success }.count
        case .noAccount: engine.sessions.filter { $0.dualResult?.outcome == .noAccount }.count
        case .permDisabled: engine.sessions.filter { $0.dualResult?.outcome == .permDisabled }.count
        case .tempDisabled: engine.sessions.filter { $0.dualResult?.outcome == .tempDisabled }.count
        case .unsure: engine.sessions.filter { $0.dualResult?.outcome == .unsure }.count
        case .error: engine.sessions.filter { $0.dualResult?.outcome == .error }.count
        }
    }
}

// MARK: - Live Test Card

struct LiveTestCard: View {
    let session: ConcurrentSession
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            dualSitePanels
                .padding(.horizontal, 14)

            if let result = session.dualResult {
                resultDescription(result)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            progressBar
                .padding(.horizontal, 14)
                .padding(.top, 10)

            statusFooter
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .onTapGesture { onTap() }
    }

    // MARK: - Title

    private var cardTitle: some View {
        HStack {
            Text(session.credential.username)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)
                .lineLimit(1)

            if !session.passwordPhaseLabel.isEmpty {
                Text(session.passwordPhaseLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(NeonTheme.neonCyan.opacity(0.12), in: .capsule)
            }

            if session.isFlaggedForReview {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(NeonTheme.neonYellow)
            }

            Spacer()

            if let result = session.dualResult {
                outcomeBadge(result.outcome)
            } else if session.phase.isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(NeonTheme.neonGreen)
                        .frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.neonGreen)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(NeonTheme.neonGreen.opacity(0.1), in: .capsule)
            }
        }
    }

    private func outcomeBadge(_ outcome: DualLoginOutcome) -> some View {
        Text(outcome.shortName.uppercased())
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(NeonTheme.outcomeColor(outcome))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(NeonTheme.outcomeColor(outcome).opacity(0.12), in: .capsule)
    }

    // MARK: - Dual Site Panels

    private var dualSitePanels: some View {
        HStack(spacing: 8) {
            sitePanel(
                site: .joe,
                outcome: session.dualResult?.joeOutcome,
                trace: session.dualResult?.joeTrace ?? [],
                screenshotData: session.joeScreenshot
            )
            sitePanel(
                site: .ignition,
                outcome: session.dualResult?.ignitionOutcome,
                trace: session.dualResult?.ignitionTrace ?? [],
                screenshotData: session.ignitionScreenshot
            )
        }
    }

    private func sitePanel(site: AutomationSite, outcome: DualLoginOutcome?, trace: [TraceEntry], screenshotData: Data?) -> some View {
        let bgColor: Color = site == .joe
            ? Color(red: 0.08, green: 0.08, blue: 0.10)
            : Color(red: 0.05, green: 0.08, blue: 0.16)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Spacer()
                siteTitle(site: site)
                Spacer()
            }

            if let data = screenshotData, let uiImage = UIImage(data: data) {
                Color.clear
                    .frame(height: 60)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 6))
            } else if !trace.isEmpty {
                traceLines(trace: trace, site: site)
            } else {
                phaseLines(site: site)
            }

            if let outcome {
                HStack {
                    Spacer()
                    siteOutcomePill(outcome)
                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(bgColor, in: .rect(cornerRadius: 10))
    }

    private func siteTitle(site: AutomationSite) -> some View {
        Group {
            if site == .joe {
                Text("Joe")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
            } else {
                HStack(spacing: 2) {
                    Text("Ignition")
                        .font(.system(size: 18, weight: .bold))
                    Text("\u{2713}")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NeonTheme.neonOrange)
                }
                .foregroundStyle(NeonTheme.textPrimary)
            }
        }
    }

    private func siteOutcomePill(_ outcome: DualLoginOutcome) -> some View {
        Text(outcome.shortName)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(NeonTheme.outcomeColor(outcome))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(NeonTheme.outcomeColor(outcome).opacity(0.15), in: .capsule)
    }

    private func traceLines(trace: [TraceEntry], site: AutomationSite) -> some View {
        let entries = trace.suffix(4)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(entries)) { entry in
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

    private func phaseLines(site: AutomationSite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch session.phase {
            case .queued:
                phaseLine("Waiting in queue...", color: NeonTheme.textTertiary)
            case .launching:
                phaseLine("Launching browser...", color: NeonTheme.neonCyan)
            case .navigating:
                phaseLine("Loading login page...", color: NeonTheme.neonCyan)
                phaseLine(String(site.defaultLoginURL.prefix(28)) + "...", color: NeonTheme.textTertiary)
            case .running:
                phaseLine("Session active", color: NeonTheme.neonGreen)
                phaseLine("Attempt in progress...", color: NeonTheme.textTertiary)
            case .waitingForElement:
                phaseLine("Waiting for elements...", color: NeonTheme.neonOrange)
                phaseLine("JS settlement check", color: NeonTheme.textTertiary)
            case .fillingForm:
                phaseLine("Filling credentials...", color: NeonTheme.neonCyan)
                phaseLine(String(session.credential.username.prefix(20)) + "...", color: NeonTheme.textTertiary)
            case .asserting:
                phaseLine("Checking response...", color: NeonTheme.neonPurple)
                phaseLine("Button color revert wait", color: NeonTheme.textTertiary)
            case .screenshotting:
                phaseLine("Capturing proof...", color: NeonTheme.neonGreen)
            default:
                phaseLine(session.phase.displayName, color: NeonTheme.textTertiary)
            }
        }
    }

    private func phaseLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Result Description

    private func resultDescription(_ result: DualLoginResult) -> some View {
        Text(descriptionText(result))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NeonTheme.textSecondary)
            .lineLimit(2)
    }

    private func descriptionText(_ result: DualLoginResult) -> String {
        switch result.outcome {
        case .success:
            var sites: [String] = []
            if result.joeOutcome == .success { sites.append("Joe") }
            if result.ignitionOutcome == .success { sites.append("Ignition") }
            return "Successful login on \(sites.joined(separator: " & ")). Session cookies saved."
        case .noAccount:
            return "4/4 attempts on both sites. All incorrect password — no account exists."
        case .permDisabled:
            var sites: [String] = []
            if result.joeOutcome == .permDisabled { sites.append("Joe") }
            if result.ignitionOutcome == .permDisabled { sites.append("Ignition") }
            return "Permanently disabled on \(sites.joined(separator: " & ")). Early-stop applied."
        case .tempDisabled:
            var sites: [String] = []
            if result.joeOutcome == .tempDisabled { sites.append("Joe") }
            if result.ignitionOutcome == .tempDisabled { sites.append("Ignition") }
            return "Temporarily disabled on \(sites.joined(separator: " & ")) — account confirmed."
        case .unsure:
            return "Mixed results — Joe: \(result.joeOutcome.shortName), Ign: \(result.ignitionOutcome.shortName). Review needed."
        case .error:
            return result.errorMessage ?? "Error during login attempt."
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
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

    // MARK: - Status Footer

    private var statusFooter: some View {
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
                            Circle()
                                .fill(NeonTheme.outcomeColor(result.joeOutcome))
                                .frame(width: 4, height: 4)
                            Text("Joe: \(result.joeOutcome.shortName)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NeonTheme.textSecondary)
                        }
                        HStack(spacing: 3) {
                            Circle()
                                .fill(NeonTheme.outcomeColor(result.ignitionOutcome))
                                .frame(width: 4, height: 4)
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

    private var borderColor: Color {
        if let result = session.dualResult {
            return NeonTheme.outcomeColor(result.outcome)
        }
        if session.phase.isActive { return NeonTheme.neonGreen }
        return NeonTheme.cardBorder
    }
}
