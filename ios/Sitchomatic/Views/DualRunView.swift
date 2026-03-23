import SwiftUI
import UIKit

struct DualRunView: View {
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var settings = AutomationSettings.shared
    @State private var credentials: [LoginCredential] = PersistenceService.shared.loadCredentials()
    @State private var selectedSession: ConcurrentSession?
    @State private var sessionFilter: SessionVisibilityFilter = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                controlPanel
                liveOverviewSection
                categoryBreakdownSection
                sessionSection
                if !engine.isRunning && engine.state != .completed {
                    configSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Dual Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedSession) { session in
            SessionProofSheet(session: session)
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: engine.state.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(engine.isRunning ? NeonTheme.neonCyan : NeonTheme.textTertiary)
                        Text(engine.state.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NeonTheme.textPrimary)
                    }

                    Text("\(enabledCredentialCount) enabled credentials \u{2022} \(settings.maxConcurrentPairs) max pairs")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.textTertiary)
                }

                Spacer()

                if engine.isRunning {
                    HStack(spacing: 8) {
                        Button {
                            if engine.state == .paused {
                                engine.resume()
                            } else {
                                engine.pause()
                            }
                        } label: {
                            Image(systemName: engine.state == .paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NeonTheme.neonCyan)
                                .frame(width: 36, height: 36)
                                .background(NeonTheme.neonCyan.opacity(0.12), in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonCyan.opacity(0.3), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            engine.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NeonTheme.neonRed)
                                .frame(width: 36, height: 36)
                                .background(NeonTheme.neonRed.opacity(0.12), in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonRed.opacity(0.3), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        startDualRun()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 12))
                            Text("Start Dual Run")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(NeonTheme.neonGreen, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .neonGlow(NeonTheme.neonGreen, radius: 4)
                    .disabled(enabledCredentialCount == 0)
                    .opacity(enabledCredentialCount == 0 ? 0.4 : 1)
                }
            }

            HStack(spacing: 8) {
                neonMetricPill(title: "Health", value: engine.healthScore.formatted(.percent.precision(.fractionLength(0))), color: NeonTheme.healthColor(engine.healthScore))
                neonMetricPill(title: "Wave", value: "\(engine.currentWave)/\(max(engine.totalWaves, 1))", color: NeonTheme.neonCyan)
                neonMetricPill(title: "Runtime", value: engine.elapsedFormatted, color: NeonTheme.textSecondary)
            }

            if engine.retryableCount > 0 && !engine.isRunning {
                Button {
                    retryFailed()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Retry \(engine.retryableCount) Failed")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(NeonTheme.neonOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(NeonTheme.neonOrange.opacity(0.1), in: .capsule)
                    .overlay(Capsule().stroke(NeonTheme.neonOrange.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(engine.isRunning ? NeonTheme.neonCyan.opacity(0.2) : NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - Live Overview

    private var liveOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Overview")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(engine.isRunning ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(engine.isRunning ? "Active" : "Ready")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(engine.isRunning ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                }
            }

            NeonProgressBar(progress: engine.overallProgress, height: 4)

            HStack(spacing: 8) {
                neonStatTile(title: "Success", value: "\(engine.succeededCount)", color: NeonTheme.neonGreen)
                neonStatTile(title: "Failed", value: "\(engine.failedCount)", color: NeonTheme.neonRed)
                neonStatTile(title: "Active", value: "\(engine.activeCount)", color: NeonTheme.neonCyan)
            }

            HStack(spacing: 8) {
                neonStatTile(title: "Queued", value: "\(engine.queuedCount)", color: NeonTheme.textTertiary)
                neonStatTile(title: "Concurrency", value: "\(engine.effectiveConcurrency)", color: NeonTheme.neonIndigo)
                neonStatTile(title: "Speed", value: settings.speedMode.displayName, color: NeonTheme.neonOrange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Result Categories")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)

            let columns: [GridItem] = [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ]

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(DualLoginOutcome.allCases, id: \.self) { outcome in
                    neonCategoryTile(outcome: outcome)
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

    private func neonCategoryTile(outcome: DualLoginOutcome) -> some View {
        let count: Int = {
            switch outcome {
            case .success: engine.succeededCount
            case .noAccount: engine.noAccountCount
            case .permDisabled: engine.permDisabledCount
            case .tempDisabled: engine.tempDisabledCount
            case .unsure: engine.unsureCount
            case .error: engine.errorCount
            }
        }()

        return HStack(spacing: 5) {
            Image(systemName: outcome.iconName)
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.outcomeColor(outcome))
            VStack(alignment: .leading, spacing: 1) {
                Text(outcome.shortName)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                Text("\(count)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(NeonTheme.outcomeColor(outcome))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(NeonTheme.outcomeColor(outcome).opacity(0.06), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.outcomeColor(outcome).opacity(0.1), lineWidth: 0.5))
    }

    // MARK: - Session Section

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Session Results")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NeonTheme.textPrimary)
                    Text("Every result includes its Playwright proof screenshots.")
                        .font(.system(size: 10))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
                Spacer()
                Text("\(filteredSessions.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            sessionFilterBar

            if filteredSessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 28))
                        .foregroundStyle(NeonTheme.textTertiary)
                    Text("No Sessions")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NeonTheme.textSecondary)
                    Text("Start a dual run to see live activity, proof screenshots, and per-site outcomes here.")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NeonTheme.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                )
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

    // MARK: - Config Section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)

            VStack(spacing: 10) {
                HStack {
                    Text("Speed Mode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NeonTheme.textSecondary)
                    Spacer()
                    Picker("", selection: $settings.speedMode) {
                        ForEach(SpeedMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(NeonTheme.neonCyan)
                }

                HStack {
                    Text("Concurrent Pairs")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NeonTheme.textSecondary)
                    Spacer()
                    Stepper("\(settings.maxConcurrentPairs)", value: $settings.maxConcurrentPairs, in: 1...12)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.neonCyan)
                }

                ForEach(settings.availableSites) { site in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(site.displayName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NeonTheme.textSecondary)

                        TextField(site.defaultLoginURL, text: siteURLBinding(for: site))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(NeonTheme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.cardBorder, lineWidth: 0.5))

                        Text(primarySelectorSummary(for: site))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(NeonTheme.textTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
        .onChange(of: settings.speedMode) { _, _ in settings.save() }
        .onChange(of: settings.maxConcurrentPairs) { _, _ in settings.save() }
        .onChange(of: settings.joeURL) { _, _ in settings.save() }
        .onChange(of: settings.ignitionURL) { _, _ in settings.save() }
    }

    // MARK: - Helpers

    private func neonMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.06), in: .capsule)
        .overlay(Capsule().stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    private func neonStatTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 12))
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

    private func startDualRun() {
        credentials = PersistenceService.shared.loadCredentials()
        settings.save()

        engine.startDualRun(
            credentials: credentials,
            joeFlow: { page, credential, speed in
                try await SiteLoginAutomationService.shared.executeLogin(
                    on: page,
                    site: .joe,
                    credential: credential,
                    speedMode: speed,
                    overrideURL: settings.loginURL(for: .joe)
                )
            },
            ignitionFlow: { page, credential, speed in
                try await SiteLoginAutomationService.shared.executeLogin(
                    on: page,
                    site: .ignition,
                    credential: credential,
                    speedMode: speed,
                    overrideURL: settings.loginURL(for: .ignition)
                )
            }
        )
    }

    private func retryFailed() {
        engine.retryFailed(
            joeFlow: { page, credential, speed in
                try await SiteLoginAutomationService.shared.executeLogin(
                    on: page,
                    site: .joe,
                    credential: credential,
                    speedMode: speed,
                    overrideURL: settings.loginURL(for: .joe)
                )
            },
            ignitionFlow: { page, credential, speed in
                try await SiteLoginAutomationService.shared.executeLogin(
                    on: page,
                    site: .ignition,
                    credential: credential,
                    speedMode: speed,
                    overrideURL: settings.loginURL(for: .ignition)
                )
            }
        )
    }

    private func siteURLBinding(for site: AutomationSite) -> Binding<String> {
        Binding(
            get: { settings.loginURL(for: site) },
            set: { settings.setLoginURL($0, for: site) }
        )
    }

    private func primarySelectorSummary(for site: AutomationSite) -> String {
        let usernameSelector: String = site.usernameSelectors.first ?? "n/a"
        let passwordSelector: String = site.passwordSelectors.first ?? "n/a"
        let submitSelector: String = site.submitSelectors.first ?? "n/a"
        return "Selectors: \(usernameSelector) \u{2022} \(passwordSelector) \u{2022} \(submitSelector)"
    }
}
