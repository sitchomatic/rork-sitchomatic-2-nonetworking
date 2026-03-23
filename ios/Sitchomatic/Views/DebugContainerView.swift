import SwiftUI
import UIKit

struct DebugContainerView: View {
    @State private var logger = DebugLogger.shared
    @State private var orchestrator = PlaywrightOrchestrator.shared
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var pool = WebViewPool.shared
    @State private var crashProtection = CrashProtectionService.shared
    @State private var recovery = SessionRecoveryService.shared
    @State private var backgroundService = BackgroundTaskService.shared
    @State private var selectedCategory: DebugLogger.LogCategory?
    @State private var minimumLevel: DebugLogger.LogLevel = .debug
    @State private var searchText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                diagnosticsCard
                categoryFilterSection
                levelFilterSection
                logStreamSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        logger.clear()
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }

                    Button {
                        UIPasteboard.general.string = logger.exportLog()
                    } label: {
                        Label("Copy All Logs", systemImage: "doc.on.doc")
                    }

                    Button {
                        UIPasteboard.general.string = engine.engineDiagnostics
                    } label: {
                        Label("Copy Engine Diagnostics", systemImage: "gauge.badge.plus")
                    }

                    Button {
                        UIPasteboard.general.string = orchestrator.diagnosticSummary
                    } label: {
                        Label("Copy Orchestrator Diagnostics", systemImage: "stethoscope")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pool.emergencyPurgeAll()
                    } label: {
                        Label("Emergency Purge Pool", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(NeonTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Diagnostics Card

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 12))
                        .foregroundStyle(NeonTheme.neonCyan)
                    Text("DIAGNOSTICS")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                Spacer()
                Text("\(filteredEntries.count) lines")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
            }

            VStack(spacing: 6) {
                diagRow(label: "Engine", value: engine.state.displayName, detail: engine.healthScore.formatted(.percent.precision(.fractionLength(0))), color: NeonTheme.healthColor(engine.healthScore))
                diagRow(label: "Memory", value: String(format: "%.0f MB", crashProtection.currentMemoryUsageMB), detail: crashProtection.memoryPressureLevel.rawValue.capitalized, color: NeonTheme.memoryColor(crashProtection.memoryPressureLevel))
                diagRow(label: "Pool", value: "\(pool.activeCount) active", detail: pool.diagnosticSummary, color: NeonTheme.neonCyan)
                diagRow(label: "Recovery", value: recovery.hasResumableCheckpoint() ? "Checkpoint" : "Clear", detail: recovery.diagnosticSummary, color: recovery.hasResumableCheckpoint() ? NeonTheme.neonOrange : NeonTheme.neonGreen)
                diagRow(label: "Background", value: backgroundLabel, detail: backgroundService.diagnosticSummary, color: backgroundService.isBackgroundTimeLow ? NeonTheme.neonOrange : NeonTheme.neonIndigo)
                diagRow(label: "Errors", value: "\(logger.recentErrors.count)", detail: orchestrator.networkStatusSummary, color: logger.recentErrors.isEmpty ? NeonTheme.neonGreen : NeonTheme.neonRed)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private func diagRow(label: String, value: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Category Filter

    private var categoryFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORY")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    neonChip(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(DebugLogger.LogCategory.allCases, id: \.rawValue) { category in
                        neonChip(title: category.title, isSelected: selectedCategory == category) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    // MARK: - Level Filter

    private var levelFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEVERITY")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DebugLogger.LogLevel.allCases, id: \.rawValue) { level in
                        neonChip(title: level.title, isSelected: minimumLevel == level) {
                            minimumLevel = level
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    // MARK: - Log Stream

    private var logStreamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.neonGreen)
                    Text("LOG STREAM")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(searchText.isEmpty ? NeonTheme.neonGreen : NeonTheme.neonCyan)
                        .frame(width: 5, height: 5)
                    Text(searchText.isEmpty ? "Realtime" : "Filtered")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(searchText.isEmpty ? NeonTheme.neonGreen : NeonTheme.neonCyan)
                }
            }

            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(NeonTheme.textTertiary)
                    Text(searchText.isEmpty ? "No Matching Logs" : "No Search Results")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NeonTheme.textSecondary)
                    Text(searchText.isEmpty ? "Adjust severity or category filters." : "Try a different search term.")
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
                LazyVStack(spacing: 6) {
                    ForEach(filteredEntries.suffix(300).reversed()) { entry in
                        logEntryRow(entry)
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: DebugLogger.LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.level.title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(neonLogColor(entry.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(neonLogColor(entry.level).opacity(0.1), in: .capsule)

                Text(entry.category.title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)

                Spacer()

                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeonTheme.textDim)
            }

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NeonTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - Helpers

    private func neonChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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
        .foregroundStyle(isSelected ? NeonTheme.neonGreen : NeonTheme.textSecondary)
    }

    private func neonLogColor(_ level: DebugLogger.LogLevel) -> Color {
        switch level {
        case .trace: NeonTheme.textDim
        case .debug: NeonTheme.textTertiary
        case .info: NeonTheme.neonCyan
        case .warning: NeonTheme.neonOrange
        case .error: NeonTheme.neonRed
        case .critical: NeonTheme.neonMagenta
        }
    }

    private var filteredEntries: [DebugLogger.LogEntry] {
        logger.entries
            .filter { entry in
                guard entry.level >= minimumLevel else { return false }
                if let selectedCategory, entry.category != selectedCategory {
                    return false
                }
                if searchText.isEmpty {
                    return true
                }
                let query: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return entry.message.localizedStandardContains(query)
                    || entry.category.title.localizedStandardContains(query)
                    || entry.level.title.localizedStandardContains(query)
            }
    }

    private var backgroundLabel: String {
        if backgroundService.remainingBackgroundTime > 900 {
            return "Foreground"
        }
        if backgroundService.remainingBackgroundTime == 0 {
            return "Idle"
        }
        return "\(Int(backgroundService.remainingBackgroundTime))s"
    }
}
