import SwiftUI
import UIKit

struct DashboardView: View {
    @Binding private var selectedTab: AppTab

    @State private var orchestrator = PlaywrightOrchestrator.shared
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var crashProtection = CrashProtectionService.shared
    @State private var settings = AutomationSettings.shared
    @State private var backgroundService = BackgroundTaskService.shared
    @State private var pool = WebViewPool.shared
    @State private var lifetimeBudget = WebViewLifetimeBudgetService.shared
    @State private var sessionRecovery = SessionRecoveryService.shared
    @State private var selectedSession: ConcurrentSession?
    @State private var sessionFilter: SessionVisibilityFilter = .all
    @State private var credentials: [LoginCredential] = []

    init(selectedTab: Binding<AppTab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pairsStatusHeader
                healthAndStatsSection
                quickActionRow
                CredentialInsightsCard(
                    credentials: credentials,
                    onTapCredentials: { selectedTab = .credentials }
                )
                categoryGaugesSection
                systemHealthRow
                toolsSection
                sessionFeedSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Sitchomatic v16")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                connectionBadge
            }
        }
        .navigationDestination(for: DashboardDestination.self) { destination in
            switch destination {
            case .dualFind:
                DualFindContainerView()
            case .recorder:
                FlowRecorderContainerView()
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionProofSheet(session: session)
        }
        .task {
            credentials = PersistenceService.shared.loadCredentials()
        }
    }

    // MARK: - Pairs Status Header

    private var pairsStatusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairs Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeonTheme.textTertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(engine.succeededCount)")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeonTheme.neonGreen)
                            .neonGlow(NeonTheme.neonGreen, radius: 4)
                        Text("/\(engine.sessions.count)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NeonTheme.textSecondary)
                    }

                    HStack(spacing: 6) {
                        if engine.isRunning {
                            Circle()
                                .fill(NeonTheme.neonGreen)
                                .frame(width: 6, height: 6)
                                .neonGlow(NeonTheme.neonGreen, radius: 3)
                            Text("Processing")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NeonTheme.neonGreen)
                        } else {
                            Circle()
                                .fill(NeonTheme.textTertiary)
                                .frame(width: 6, height: 6)
                            Text(engine.state.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NeonTheme.textTertiary)
                        }
                    }
                }

                Spacer()

                Button {
                    selectedTab = .run
                } label: {
                    Text("Run")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(NeonTheme.neonGreen, in: .capsule)
                }
                .neonGlow(NeonTheme.neonGreen, radius: 6)
            }

            NeonProgressBar(
                progress: engine.sessions.isEmpty ? 0 : engine.overallProgress,
                height: 4
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeonTheme.neonGreen.opacity(engine.isRunning ? 0.2 : 0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Health Ring + Stats Grid

    private var healthAndStatsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                statTile(value: "\(engine.succeededCount)", label: "Success", color: NeonTheme.neonGreen)
                statTile(value: "\(engine.failedCount)", label: "Failed", color: NeonTheme.neonRed)
                statTile(value: "\(engine.activeCount)", label: "Active", color: NeonTheme.neonCyan)
            }

            HealthRingView(
                progress: engine.healthScore,
                label: "\(Int(engine.healthScore * 100))%",
                stateLabel: engine.isRunning ? "Active" : engine.state.displayName,
                size: 130
            )

            VStack(spacing: 6) {
                statTile(value: "\(engine.queuedCount)", label: "Queued", color: NeonTheme.textTertiary)
                statTile(value: "\(enabledCredentialCount)", label: "Creds", color: NeonTheme.textPrimary)
                statTile(value: "\(engine.effectiveConcurrency)", label: "Pairs", color: NeonTheme.neonCyan)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .frame(width: 56, height: 44)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 8))
    }

    // MARK: - Quick Action Row

    private var quickActionRow: some View {
        HStack(spacing: 10) {
            quickActionButton(
                title: "Credentials",
                symbol: "person.badge.key.fill",
                tint: NeonTheme.neonCyan,
                badge: enabledCredentialCount
            ) { selectedTab = .credentials }

            quickActionButton(
                title: "Pairs",
                symbol: "link",
                tint: NeonTheme.neonGreen,
                badge: orchestrator.activePairedSessions
            ) { selectedTab = .run }

            quickActionButton(
                title: "Health",
                symbol: "heart.fill",
                tint: NeonTheme.healthColor(engine.healthScore),
                badge: 0
            ) { selectedTab = .debug }

            quickActionButton(
                title: "Sessions",
                symbol: "antenna.radiowaves.left.and.right",
                tint: NeonTheme.neonPurple,
                badge: engine.activeCount
            ) { selectedTab = .run }
        }
    }

    private func quickActionButton(title: String, symbol: String, tint: Color, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(tint, in: .capsule)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NeonTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Gauges

    private var categoryGaugesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                GaugeIndicatorView(value: Double(engine.succeededCount), maxValue: max(Double(engine.sessions.count), 1), label: "Success", count: "\(engine.succeededCount)", color: NeonTheme.neonGreen)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.failedCount), maxValue: max(Double(engine.sessions.count), 1), label: "Failed", count: "\(engine.failedCount)", color: NeonTheme.neonRed)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.activeCount), maxValue: max(Double(engine.sessions.count), 1), label: "Active", count: "\(engine.activeCount)", color: NeonTheme.neonCyan)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.queuedCount), maxValue: max(Double(engine.sessions.count), 1), label: "Queued", count: "\(engine.queuedCount)", color: NeonTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                GaugeIndicatorView(value: Double(engine.noAccountCount), maxValue: max(Double(engine.sessions.count), 1), label: "No ACC", count: "\(engine.noAccountCount)", color: NeonTheme.neonIndigo)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.tempDisabledCount), maxValue: max(Double(engine.sessions.count), 1), label: "Temp", count: "\(engine.tempDisabledCount)", color: NeonTheme.neonOrange)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.permDisabledCount), maxValue: max(Double(engine.sessions.count), 1), label: "Perm", count: "\(engine.permDisabledCount)", color: NeonTheme.neonRed)
                    .frame(maxWidth: .infinity)
                GaugeIndicatorView(value: Double(engine.errorCount), maxValue: max(Double(engine.sessions.count), 1), label: "Error", count: "\(engine.errorCount)", color: NeonTheme.neonYellow)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - System Health Row

    private var systemHealthRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("System Health Waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NeonTheme.textTertiary)
                WaveformView(barCount: 36, color: NeonTheme.neonGreen)
                HStack {
                    Text(engine.state.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(engine.isRunning ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                    Spacer()
                    Text(engine.elapsedFormatted)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(NeonTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                    )
            )

            VStack(spacing: 8) {
                Text("Memory Status")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NeonTheme.textTertiary)

                ZStack {
                    Circle()
                        .stroke(NeonTheme.memoryColor(crashProtection.memoryPressureLevel).opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: memoryUsageFraction)
                        .stroke(
                            NeonTheme.memoryColor(crashProtection.memoryPressureLevel),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(crashProtection.currentMemoryUsageMB))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.memoryColor(crashProtection.memoryPressureLevel))
                }
                .frame(width: 48, height: 48)

                Text("\(crashProtection.memoryPressureLevel.rawValue.capitalized)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NeonTheme.memoryColor(crashProtection.memoryPressureLevel))
            }
            .padding(12)
            .frame(width: 100)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(NeonTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        HStack(spacing: 12) {
            NavigationLink(value: DashboardDestination.dualFind) {
                toolCard(title: "Dual Find", subtitle: "Selector search", symbol: "magnifyingglass.circle.fill", tint: NeonTheme.neonCyan)
            }
            .buttonStyle(.plain)

            NavigationLink(value: DashboardDestination.recorder) {
                toolCard(title: "Recorder", subtitle: "Capture flows", symbol: "record.circle.fill", tint: NeonTheme.neonRed)
            }
            .buttonStyle(.plain)
        }
    }

    private func toolCard(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Session Feed

    private var sessionFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
                Spacer()
                Text("\(filteredSessions.count) shown")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
            }

            sessionFilterBar

            if filteredSessions.isEmpty {
                emptySessionState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSessions) { session in
                        SessionCardView(
                            session: session,
                            onTap: { selectedSession = session },
                            onRetry: { engine.enqueueRetry(session.credential) },
                            onCopy: { UIPasteboard.general.string = session.credential.username },
                            onFlag: { session.toggleFlagged() }
                        )
                    }
                }
            }
        }
    }

    private var sessionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionVisibilityFilter.allCases, id: \.self) { filter in
                    Button {
                        sessionFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 8))
                            Text(filter.title)
                            Text("\(count(for: filter))")
                                .foregroundStyle(sessionFilter == filter ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(sessionFilter == filter ? NeonTheme.neonGreen.opacity(0.12) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            Capsule()
                                .stroke(sessionFilter == filter ? NeonTheme.neonGreen.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sessionFilter == filter ? NeonTheme.neonGreen : NeonTheme.textSecondary)
                }
            }
        }
        .contentMargins(.horizontal, 0)
    }

    private var emptySessionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 28))
                .foregroundStyle(NeonTheme.textTertiary)
            Text("No Sessions")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NeonTheme.textSecondary)
            Text("Start a dual run to see live progress, proof screenshots, and outcome breakdowns here.")
                .font(.system(size: 11))
                .foregroundStyle(NeonTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeonTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Connection Badge

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(orchestrator.isReady ? NeonTheme.neonGreen : NeonTheme.neonRed)
                .frame(width: 6, height: 6)
                .neonGlow(orchestrator.isReady ? NeonTheme.neonGreen : NeonTheme.neonRed, radius: 3)
            Text(orchestrator.isReady ? "LIVE" : "OFF")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(orchestrator.isReady ? NeonTheme.neonGreen : NeonTheme.neonRed)
        }
    }

    // MARK: - Data Helpers

    private var filteredSessions: [ConcurrentSession] {
        let base: [ConcurrentSession]
        switch sessionFilter {
        case .all:
            base = engine.sessions
        case .active:
            base = engine.sessions.filter { $0.phase.isActive || $0.phase == .queued }
        case .success:
            base = engine.sessions.filter { $0.dualResult?.outcome == .success }
        case .noAccount:
            base = engine.sessions.filter { $0.dualResult?.outcome == .noAccount }
        case .permDisabled:
            base = engine.sessions.filter { $0.dualResult?.outcome == .permDisabled }
        case .tempDisabled:
            base = engine.sessions.filter { $0.dualResult?.outcome == .tempDisabled }
        case .unsure:
            base = engine.sessions.filter { $0.dualResult?.outcome == .unsure }
        case .error:
            base = engine.sessions.filter { $0.dualResult?.outcome == .error }
        }

        return base.sorted { lhs, rhs in
            if lhs.phase.isActive != rhs.phase.isActive {
                return lhs.phase.isActive
            }
            if lhs.phase == .failed && rhs.phase != .failed {
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

    private var enabledCredentialCount: Int {
        credentials.filter(\.isEnabled).count
    }

    private var memoryUsageFraction: Double {
        let usage = crashProtection.currentMemoryUsageMB
        let threshold = Double(settings.memoryEmergencyThresholdMB)
        guard threshold > 0 else { return 0 }
        return min(usage / threshold, 1.0)
    }
}
