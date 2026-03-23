import SwiftUI
import UIKit

nonisolated struct DualFindSiteOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
}

nonisolated enum DualFindSelectorFamily: String, Sendable, CaseIterable {
    case username
    case password
    case submit

    var title: String {
        switch self {
        case .username: "Username"
        case .password: "Password"
        case .submit: "Submit"
        }
    }

    var icon: String {
        switch self {
        case .username: "person.fill"
        case .password: "key.fill"
        case .submit: "arrow.right.circle.fill"
        }
    }

    func selectors(for site: AutomationSite) -> [String] {
        switch self {
        case .username: site.usernameSelectors
        case .password: site.passwordSelectors
        case .submit: site.submitSelectors
        }
    }
}

nonisolated struct DualFindMatch: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let index: Int
    let textPreview: String
    let attributeSummary: String
    let isVisible: Bool

    init(id: UUID = UUID(), index: Int, textPreview: String, attributeSummary: String, isVisible: Bool) {
        self.id = id
        self.index = index
        self.textPreview = textPreview
        self.attributeSummary = attributeSummary
        self.isVisible = isVisible
    }
}

nonisolated struct DualFindArtifact: Codable, Sendable {
    let targetSite: String
    let searchURL: String
    let resolvedPageURL: String
    let selectorFamily: String
    let selector: String
    let runTimestamp: Date
    let matches: [DualFindMatch]
    let screenshotPath: String?
}

nonisolated enum ProbeCellStatus: Sendable {
    case idle
    case probing
    case found(count: Int, allVisible: Bool)
    case notFound
    case error(String)

    var icon: String {
        switch self {
        case .idle: "circle.dotted"
        case .probing: "arrow.triangle.2.circlepath"
        case .found(_, let allVisible): allVisible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .notFound: "xmark.circle.fill"
        case .error: "bolt.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: NeonTheme.textTertiary
        case .probing: NeonTheme.neonCyan
        case .found(_, let allVisible): allVisible ? NeonTheme.neonGreen : NeonTheme.neonOrange
        case .notFound: NeonTheme.neonRed
        case .error: NeonTheme.neonYellow
        }
    }

    var label: String {
        switch self {
        case .idle: "—"
        case .probing: "..."
        case .found(let count, let allVisible): allVisible ? "\(count) OK" : "\(count) hidden"
        case .notFound: "Missing"
        case .error: "Error"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .found, .notFound, .error: true
        default: false
        }
    }
}

struct ProbeCell: Identifiable {
    let id: String
    let site: AutomationSite
    let family: DualFindSelectorFamily
    var status: ProbeCellStatus = .idle
    var matches: [DualFindMatch] = []
    var selectorUsed: String = ""
}

struct DualFindContainerView: View {
    @State private var orchestrator: PlaywrightOrchestrator = .shared
    @State private var settings: AutomationSettings = .shared
    @State private var recovery: SessionRecoveryService = .shared

    @State private var probeCells: [ProbeCell] = []
    @State private var isFullProbing: Bool = false
    @State private var lastProbeDate: Date?
    @State private var joeScreenshot: Data?
    @State private var ignitionScreenshot: Data?
    @State private var expandedCellID: String?
    @State private var probeError: String?
    @State private var showAdvanced: Bool = false

    @State private var advSelectedSiteID: String = AutomationSite.joe.rawValue
    @State private var advSelectorFamily: DualFindSelectorFamily = .username
    @State private var advCustomURL: String = ""
    @State private var advSelectorQuery: String = AutomationSite.joe.usernameSelectors.first ?? ""
    @State private var advResults: [DualFindMatch] = []
    @State private var advIsSearching: Bool = false
    @State private var advProofData: Data?
    @State private var advError: String?
    @State private var advLastDate: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                fullProbeCard
                if !probeCells.isEmpty {
                    healthMatrixCard
                }
                if joeScreenshot != nil || ignitionScreenshot != nil {
                    proofScreenshotsCard
                }
                if probeError != nil {
                    probeErrorCard
                }
                ppsrCard
                advancedSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Dual Find")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                connectionBadge
            }
        }
        .task {
            initializeProbeCells()
        }
    }

    // MARK: - Full Probe Card

    private var fullProbeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selector Health Check")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NeonTheme.textPrimary)
                    Text("Probe all selectors on both sites with one tap.")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
                Spacer()
                if let lastProbeDate {
                    Text(lastProbeDate, style: .relative)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
            }

            Button {
                Task { await runFullProbe() }
            } label: {
                HStack(spacing: 10) {
                    if isFullProbing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 14))
                    }
                    Text(isFullProbing ? "Probing All Selectors..." : "Full Probe")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isFullProbing
                        ? NeonTheme.neonCyan.opacity(0.6)
                        : NeonTheme.neonCyan,
                    in: .rect(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .disabled(isFullProbing)
            .neonGlow(NeonTheme.neonCyan, radius: isFullProbing ? 2 : 6)
            .sensoryFeedback(.impact(weight: .medium), trigger: isFullProbing)

            HStack(spacing: 10) {
                statPill(title: "Sites", value: "\(AutomationSite.allCases.count)", tint: NeonTheme.neonCyan)
                statPill(title: "Selectors", value: "\(DualFindSelectorFamily.allCases.count * AutomationSite.allCases.count)", tint: NeonTheme.neonGreen)
                statPill(title: "Storage", value: String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB), tint: NeonTheme.textTertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFullProbing ? NeonTheme.neonCyan.opacity(0.3) : NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - Health Matrix

    private var healthMatrixCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health Matrix")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
                Spacer()
                overallHealthBadge
            }

            VStack(spacing: 0) {
                matrixHeaderRow
                ForEach(AutomationSite.allCases) { site in
                    matrixSiteRow(site: site)
                }
            }
            .clipShape(.rect(cornerRadius: 12))

            if let expandedCellID, let cell = probeCells.first(where: { $0.id == expandedCellID }), !cell.matches.isEmpty {
                expandedDetailCard(cell: cell)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var matrixHeaderRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 70)
            ForEach(DualFindSelectorFamily.allCases, id: \.self) { family in
                VStack(spacing: 2) {
                    Image(systemName: family.icon)
                        .font(.system(size: 10))
                    Text(family.title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(NeonTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .background(Color.white.opacity(0.03))
    }

    private func matrixSiteRow(site: AutomationSite) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle()
                    .fill(siteRowColor(site))
                    .frame(width: 5, height: 5)
                Text(site == .joe ? "Joe" : "Ignition")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NeonTheme.textSecondary)
            }
            .frame(width: 70, alignment: .leading)
            .padding(.leading, 8)

            ForEach(DualFindSelectorFamily.allCases, id: \.self) { family in
                let cellID = "\(site.rawValue)_\(family.rawValue)"
                let cell = probeCells.first(where: { $0.id == cellID })
                let status = cell?.status ?? .idle

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        if expandedCellID == cellID {
                            expandedCellID = nil
                        } else {
                            expandedCellID = cellID
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: status.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(status.color)
                            .symbolEffect(.pulse, isActive: status is ProbeCellStatus && isProbing(status))
                        Text(status.label)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(status.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        expandedCellID == cellID
                            ? status.color.opacity(0.12)
                            : status.color.opacity(0.04)
                    )
                    .overlay(
                        Rectangle()
                            .stroke(expandedCellID == cellID ? status.color.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.02))
    }

    private func isProbing(_ status: ProbeCellStatus) -> Bool {
        if case .probing = status { return true }
        return false
    }

    private func siteRowColor(_ site: AutomationSite) -> Color {
        let cells = probeCells.filter { $0.site == site }
        let allGood = cells.allSatisfy {
            if case .found(_, true) = $0.status { return true }
            return false
        }
        let anyBad = cells.contains {
            if case .notFound = $0.status { return true }
            if case .error = $0.status { return true }
            return false
        }
        if allGood && !cells.isEmpty { return NeonTheme.neonGreen }
        if anyBad { return NeonTheme.neonRed }
        return NeonTheme.textTertiary
    }

    private var overallHealthBadge: some View {
        let terminal = probeCells.filter { $0.status.isTerminal }
        let good = terminal.filter {
            if case .found(_, true) = $0.status { return true }
            return false
        }
        let total = probeCells.count
        let fraction = total > 0 ? "\(good.count)/\(total)" : "—"
        let color: Color = {
            if terminal.isEmpty { return NeonTheme.textTertiary }
            if good.count == total { return NeonTheme.neonGreen }
            if good.count >= total / 2 { return NeonTheme.neonOrange }
            return NeonTheme.neonRed
        }()

        return Text(fraction)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: .capsule)
    }

    private func expandedDetailCard(cell: ProbeCell) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: cell.family.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(NeonTheme.neonCyan)
                Text("\(cell.site.displayName) → \(cell.family.title)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
                Spacer()
                Text(cell.selectorUsed)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .lineLimit(1)
            }

            ForEach(cell.matches) { match in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(match.isVisible ? NeonTheme.neonGreen : NeonTheme.neonOrange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.attributeSummary)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(NeonTheme.textSecondary)
                        if match.textPreview != "No text content" {
                            Text(match.textPreview)
                                .font(.system(size: 9))
                                .foregroundStyle(NeonTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(match.isVisible ? "Visible" : "Hidden")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(match.isVisible ? NeonTheme.neonGreen : NeonTheme.neonOrange)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Proof Screenshots

    private var proofScreenshotsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proof Captures")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let joeScreenshot, let img = UIImage(data: joeScreenshot) {
                        proofThumbnail(image: img, label: "Joe Fortune")
                    }
                    if let ignitionScreenshot, let img = UIImage(data: ignitionScreenshot) {
                        proofThumbnail(image: img, label: "Ignition Casino")
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private func proofThumbnail(image: UIImage, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(white: 0.08)
                .frame(width: 260, height: 160)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)
        }
    }

    // MARK: - Error Card

    private var probeErrorCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NeonTheme.neonRed)
            Text(probeError ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NeonTheme.neonRed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(NeonTheme.neonRed.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    // MARK: - PPSR

    private var ppsrCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PPSR")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NeonTheme.textPrimary)
                Spacer()
                Text(recovery.hasResumableCheckpoint() ? "Checkpoint Ready" : "Clear")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(recovery.hasResumableCheckpoint() ? NeonTheme.neonOrange : NeonTheme.neonGreen)
            }
            ppsrRow(label: "Storage", value: String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB), tint: NeonTheme.neonCyan)
            ppsrRow(label: "Recovery", value: recovery.diagnosticSummary, tint: recovery.hasResumableCheckpoint() ? NeonTheme.neonOrange : NeonTheme.neonGreen)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - Advanced (Manual Single Probe)

    private var advancedSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(NeonTheme.textTertiary)
                    Text("Advanced Single Probe")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NeonTheme.textSecondary)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NeonTheme.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)

            if showAdvanced {
                advancedProbeContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var advancedProbeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(advSiteOptions, id: \.id) { option in
                        Button {
                            advSelectedSiteID = option.id
                            syncAdvSelection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.symbolName)
                                Text(option.title)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(advSelectedSiteID == option.id ? NeonTheme.neonCyan.opacity(0.15) : Color.white.opacity(0.04), in: .capsule)
                            .overlay(Capsule().stroke(advSelectedSiteID == option.id ? NeonTheme.neonCyan.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(advSelectedSiteID == option.id ? NeonTheme.neonCyan : NeonTheme.textSecondary)
                    }
                }
            }
            .contentMargins(.horizontal, 0)

            Picker("Family", selection: $advSelectorFamily) {
                ForEach(DualFindSelectorFamily.allCases, id: \.self) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: advSelectorFamily) { _, _ in syncAdvSelection() }

            TextField("CSS selector", text: $advSelectorQuery)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NeonTheme.textPrimary)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.cardBorder, lineWidth: 0.5))

            if let advSelectedSite, !advSelectorFamily.selectors(for: advSelectedSite).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(advSelectorFamily.selectors(for: advSelectedSite), id: \.self) { sel in
                            Button { advSelectorQuery = sel } label: {
                                Text(sel)
                                    .font(.system(size: 9, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(advSelectorQuery == sel ? NeonTheme.neonCyan.opacity(0.12) : Color.white.opacity(0.04), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(advSelectorQuery == sel ? NeonTheme.neonCyan : NeonTheme.textTertiary)
                        }
                    }
                }
                .contentMargins(.horizontal, 0)
            }

            Button {
                Task { await performAdvancedSearch() }
            } label: {
                HStack(spacing: 8) {
                    if advIsSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(advIsSearching ? "Searching..." : "Search Selector")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(NeonTheme.neonCyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(NeonTheme.neonCyan.opacity(0.1), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.neonCyan.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(advIsSearching || advSelectorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let advError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NeonTheme.neonRed)
                    Text(advError)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeonTheme.neonRed)
                }
                .padding(10)
                .background(NeonTheme.neonRed.opacity(0.08), in: .rect(cornerRadius: 10))
            }

            if !advResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(advResults.count) match(es)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NeonTheme.textPrimary)
                        Spacer()
                        if let advLastDate {
                            Text(advLastDate, style: .relative)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(NeonTheme.textTertiary)
                        }
                    }
                    ForEach(advResults) { match in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(match.isVisible ? NeonTheme.neonGreen : NeonTheme.neonOrange)
                                .frame(width: 5, height: 5)
                            Text(match.attributeSummary)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(NeonTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(match.isVisible ? "OK" : "Hidden")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(match.isVisible ? NeonTheme.neonGreen : NeonTheme.neonOrange)
                        }
                    }
                }
            }

            if let advProofData, let img = UIImage(data: advProofData) {
                Color(white: 0.08)
                    .frame(height: 160)
                    .overlay {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
        .padding(.top, -8)
    }

    // MARK: - Helpers

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

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.06), in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.12), lineWidth: 0.5))
    }

    private func ppsrRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Advanced Helpers

    private var advSelectedSite: AutomationSite? {
        AutomationSite(rawValue: advSelectedSiteID)
    }

    private var advSiteOptions: [DualFindSiteOption] {
        AutomationSite.allCases.map {
            DualFindSiteOption(id: $0.rawValue, title: $0.displayName, symbolName: "globe")
        } + [DualFindSiteOption(id: "custom", title: "Custom", symbolName: "slider.horizontal.3")]
    }

    private func syncAdvSelection() {
        if let site = advSelectedSite {
            advSelectorQuery = advSelectorFamily.selectors(for: site).first ?? advSelectorQuery
        }
    }

    // MARK: - Full Probe Logic

    private func initializeProbeCells() {
        guard probeCells.isEmpty else { return }
        var cells: [ProbeCell] = []
        for site in AutomationSite.allCases {
            for family in DualFindSelectorFamily.allCases {
                cells.append(ProbeCell(
                    id: "\(site.rawValue)_\(family.rawValue)",
                    site: site,
                    family: family
                ))
            }
        }
        probeCells = cells
    }

    private func runFullProbe() async {
        isFullProbing = true
        probeError = nil
        joeScreenshot = nil
        ignitionScreenshot = nil
        expandedCellID = nil

        for i in probeCells.indices {
            probeCells[i].status = .probing
            probeCells[i].matches = []
        }

        do {
            if !orchestrator.isReady {
                try await orchestrator.startSession(speedMode: settings.speedMode)
            }

            await withTaskGroup(of: Void.self) { group in
                for site in AutomationSite.allCases {
                    group.addTask { @MainActor in
                        await self.probeSite(site)
                    }
                }
            }

            lastProbeDate = Date()
            persistFullProbeArtifacts()

        } catch {
            probeError = error.localizedDescription
            for i in probeCells.indices {
                if case .probing = probeCells[i].status {
                    probeCells[i].status = .error(error.localizedDescription)
                }
            }
        }

        isFullProbing = false
    }

    private func probeSite(_ site: AutomationSite) async {
        let url = settings.loginURL(for: site)
        guard !url.isEmpty else {
            for i in probeCells.indices where probeCells[i].site == site {
                probeCells[i].status = .error("No URL configured")
            }
            return
        }

        let page: PlaywrightPage
        do {
            page = try await orchestrator.newPage()
        } catch {
            for i in probeCells.indices where probeCells[i].site == site {
                probeCells[i].status = .error("Page creation failed")
            }
            return
        }

        defer { orchestrator.closePage(page) }

        do {
            try await page.goto(url, waitUntil: .networkIdle)
        } catch {
            for i in probeCells.indices where probeCells[i].site == site {
                probeCells[i].status = .error("Navigation failed")
            }
            return
        }

        for family in DualFindSelectorFamily.allCases {
            let cellID = "\(site.rawValue)_\(family.rawValue)"
            let selectors = family.selectors(for: site)
            guard let primarySelector = selectors.first else {
                if let idx = probeCells.firstIndex(where: { $0.id == cellID }) {
                    probeCells[idx].status = .notFound
                }
                continue
            }

            do {
                let locator = page.locator(primarySelector)
                let count = try await locator.count()

                if count == 0 {
                    var found = false
                    for altSelector in selectors.dropFirst() {
                        let altLocator = page.locator(altSelector)
                        let altCount = try await altLocator.count()
                        if altCount > 0 {
                            let matches = try await extractMatches(locator: altLocator, count: min(altCount, 3))
                            let allVisible = matches.allSatisfy(\.isVisible)
                            if let idx = probeCells.firstIndex(where: { $0.id == cellID }) {
                                probeCells[idx].status = .found(count: altCount, allVisible: allVisible)
                                probeCells[idx].matches = matches
                                probeCells[idx].selectorUsed = altSelector
                            }
                            found = true
                            break
                        }
                    }
                    if !found {
                        if let idx = probeCells.firstIndex(where: { $0.id == cellID }) {
                            probeCells[idx].status = .notFound
                            probeCells[idx].selectorUsed = primarySelector
                        }
                    }
                } else {
                    let matches = try await extractMatches(locator: locator, count: min(count, 3))
                    let allVisible = matches.allSatisfy(\.isVisible)
                    if let idx = probeCells.firstIndex(where: { $0.id == cellID }) {
                        probeCells[idx].status = .found(count: count, allVisible: allVisible)
                        probeCells[idx].matches = matches
                        probeCells[idx].selectorUsed = primarySelector
                    }
                }
            } catch {
                if let idx = probeCells.firstIndex(where: { $0.id == cellID }) {
                    probeCells[idx].status = .error("Probe failed")
                    probeCells[idx].selectorUsed = primarySelector
                }
            }
        }

        let screenshot = try? await page.screenshot()
        if site == .joe {
            joeScreenshot = screenshot
        } else {
            ignitionScreenshot = screenshot
        }
    }

    private func extractMatches(locator: Locator, count: Int) async throws -> [DualFindMatch] {
        var matches: [DualFindMatch] = []
        for index in 0..<count {
            let element = locator.nth(index)
            let textPreview = ((try? await element.textContent()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholder: String? = try? await element.getAttribute("placeholder")
            let name: String? = try? await element.getAttribute("name")
            let idValue: String? = try? await element.getAttribute("id")
            let type: String? = try? await element.getAttribute("type")
            let isVisible = (try? await element.isVisible()) ?? false

            let attributes: [String] = [
                idValue.map { "id=\($0)" },
                name.map { "name=\($0)" },
                type.map { "type=\($0)" },
                placeholder.map { "placeholder=\($0)" }
            ].compactMap { $0 }

            matches.append(DualFindMatch(
                index: index + 1,
                textPreview: textPreview.isEmpty ? "No text content" : String(textPreview.prefix(220)),
                attributeSummary: attributes.isEmpty ? "No common attributes" : attributes.joined(separator: " \u{2022} "),
                isVisible: isVisible
            ))
        }
        return matches
    }

    private func persistFullProbeArtifacts() {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName = "fullprobe_\(timestamp)"

        struct FullProbeResult: Codable {
            let timestamp: Date
            let cells: [CellResult]
        }
        struct CellResult: Codable {
            let site: String
            let family: String
            let selectorUsed: String
            let matchCount: Int
            let allVisible: Bool
            let matches: [DualFindMatch]
        }

        let cellResults: [CellResult] = probeCells.map { cell in
            let (count, visible): (Int, Bool) = {
                switch cell.status {
                case .found(let c, let v): return (c, v)
                default: return (0, false)
                }
            }()
            return CellResult(
                site: cell.site.rawValue,
                family: cell.family.rawValue,
                selectorUsed: cell.selectorUsed,
                matchCount: count,
                allVisible: visible,
                matches: cell.matches
            )
        }

        let result = FullProbeResult(timestamp: Date(), cells: cellResults)
        if let data = try? JSONEncoder().encode(result) {
            PersistentFileStorageService.shared.save(data: data, filename: "tools/dualfind/\(baseName).json")
        }
        if let joeScreenshot {
            PersistentFileStorageService.shared.save(data: joeScreenshot, filename: "tools/dualfind/\(baseName)_joe.png")
        }
        if let ignitionScreenshot {
            PersistentFileStorageService.shared.save(data: ignitionScreenshot, filename: "tools/dualfind/\(baseName)_ignition.png")
        }

        DebugLogger.shared.log("Full probe persisted: \(baseName)", category: .ppsr, level: .info)
    }

    // MARK: - Advanced Search Logic

    private func performAdvancedSearch() async {
        let url: String
        if let site = advSelectedSite {
            url = settings.loginURL(for: site)
        } else {
            url = advCustomURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let selector = advSelectorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !selector.isEmpty else { return }

        advIsSearching = true
        advResults.removeAll()
        advProofData = nil
        advError = nil

        do {
            if !orchestrator.isReady {
                try await orchestrator.startSession(speedMode: settings.speedMode)
            }

            let page = try await orchestrator.newPage()
            defer { orchestrator.closePage(page) }

            try await page.goto(url, waitUntil: .networkIdle)

            let locator = page.locator(selector)
            let count = try await locator.count()
            let matches = try await extractMatches(locator: locator, count: min(count, 5))

            advResults = matches
            advProofData = try? await page.screenshot()
            advLastDate = Date()

            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let baseName = "adv_\(advSelectedSite?.rawValue ?? "custom")_\(timestamp)"
            let artifact = DualFindArtifact(
                targetSite: advSelectedSite?.displayName ?? "Custom",
                searchURL: url,
                resolvedPageURL: page.url(),
                selectorFamily: advSelectorFamily.title,
                selector: selector,
                runTimestamp: Date(),
                matches: matches,
                screenshotPath: "tools/dualfind/\(baseName).png"
            )
            if let data = try? JSONEncoder().encode(artifact) {
                PersistentFileStorageService.shared.save(data: data, filename: "tools/dualfind/\(baseName).json")
            }
            if let screenshot = advProofData {
                PersistentFileStorageService.shared.save(data: screenshot, filename: "tools/dualfind/\(baseName).png")
            }
        } catch {
            advError = error.localizedDescription
            advLastDate = Date()
        }

        advIsSearching = false
    }
}
