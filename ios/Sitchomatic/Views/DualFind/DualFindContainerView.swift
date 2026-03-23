import SwiftUI
import UIKit

struct DualFindContainerView: View {
    @State private var orchestrator: PlaywrightOrchestrator = .shared
    @State private var settings: AutomationSettings = .shared
    @State private var recovery: SessionRecoveryService = .shared
    @State private var selectedSiteID: String = AutomationSite.joe.rawValue
    @State private var selectorFamily: DualFindSelectorFamily = .username
    @State private var customURL: String = ""
    @State private var selectorQuery: String = AutomationSite.joe.usernameSelectors.first ?? ""
    @State private var results: [DualFindMatch] = []
    @State private var isSearching: Bool = false
    @State private var hasPerformedSearch: Bool = false
    @State private var proofImageData: Data?
    @State private var lastSavedProofPath: String?
    @State private var lastSavedMetadataPath: String?
    @State private var lastErrorMessage: String?
    @State private var lastRunSummary: String?
    @State private var lastRunDate: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewCard
                configurationCard
                if proofImage != nil {
                    proofCard
                }
                resultsCard
                ppsrCard
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
        .task {
            syncSelection(forceSelectorRefresh: true)
        }
        .onChange(of: selectedSiteID) { _, _ in
            syncSelection(forceSelectorRefresh: true)
        }
        .onChange(of: selectorFamily) { _, _ in
            syncSelection(forceSelectorRefresh: selectorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: settings.joeURL) { _, _ in
            if selectedSite == .joe {
                syncSelection(forceSelectorRefresh: false)
            }
        }
        .onChange(of: settings.ignitionURL) { _, _ in
            if selectedSite == .ignition {
                syncSelection(forceSelectorRefresh: false)
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selector Probe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Text("Inspect login DOM, capture proof, and persist PPSR artifacts.")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NeonTheme.textPrimary)
                    Text("Site presets follow the Joe and Ignition profiles already configured in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(NeonTheme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Label(orchestrator.connectionStatus.displayName, systemImage: orchestrator.connectionStatus.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(orchestrator.connectionStatus == .connected ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                    Text(orchestrator.networkStatusSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 10) {
                statPill(title: "Target", value: selectedSite?.displayName ?? "Custom", tint: .cyan)
                statPill(title: "Family", value: selectorFamily.title, tint: .blue)
                statPill(title: "Storage", value: String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB), tint: .secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuration")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NeonTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(siteOptions, id: \.id) { option in
                        Button {
                            selectedSiteID = option.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: option.symbolName)
                                Text(option.title)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedSiteID == option.id ? .cyan.opacity(0.16) : .secondary.opacity(0.08), in: .capsule)
                            .overlay {
                                Capsule()
                                    .stroke(selectedSiteID == option.id ? .cyan : .secondary.opacity(0.18), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedSiteID == option.id ? .cyan : .secondary)
                    }
                }
                .contentMargins(.horizontal, 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Login URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("https://example.com/login", text: urlBinding)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Selector family")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NeonTheme.textTertiary)

                Picker("Selector family", selection: $selectorFamily) {
                    ForEach(DualFindSelectorFamily.allCases, id: \.self) { family in
                        Text(family.title)
                            .tag(family)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CSS selector")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("button[type='submit']", text: $selectorQuery)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
            }

            if !recommendedSelectors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recommended selectors")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(recommendedSelectors.count) presets")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recommendedSelectors, id: \.self) { selector in
                                Button {
                                    selectorQuery = selector
                                } label: {
                                    Text(selector)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(selectorQuery == selector ? .blue.opacity(0.14) : .secondary.opacity(0.08), in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectorQuery == selector ? .blue : .secondary)
                            }
                        }
                        .contentMargins(.horizontal, 0)
                    }
                }
            }

            Button {
                Task {
                    await performSearch()
                }
            } label: {
                HStack(spacing: 10) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isSearching ? "Searching..." : "Search Selector")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(isSearching || resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trimmedSelectorQuery.isEmpty)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matches")
                        .font(.headline)
                    Text(lastRunSummary ?? "Run a selector search to inspect visibility, attributes, and quick text previews.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lastRunDate {
                    Text(lastRunDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastErrorMessage {
                errorBanner(message: lastErrorMessage)
            } else if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Inspecting \(trimmedSelectorQuery)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if results.isEmpty {
                if hasPerformedSearch {
                    ContentUnavailableView.search(text: trimmedSelectorQuery)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ContentUnavailableView(
                        "No Probe Yet",
                        systemImage: "scope",
                        description: Text("Choose a site preset or custom URL, then run a selector probe to capture proof and PPSR metadata.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(result.isVisible ? Color.green : Color.orange)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Match \(result.index)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(result.attributeSummary)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(result.isVisible ? "Visible" : "Hidden")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.isVisible ? .green : .orange)
                            }

                            if !result.textPreview.isEmpty {
                                Text(result.textPreview)
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .background(NeonTheme.cardBackground, in: .rect(cornerRadius: 16))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var proofCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proof Capture")
                    .font(.headline)
                Spacer()
                if let lastSavedProofPath {
                    Text(lastSavedProofPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let proofImage {
                Color(white: 0.08)
                    .frame(height: 220)
                    .overlay {
                        Image(uiImage: proofImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 18))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var ppsrCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PPSR")
                    .font(.headline)
                Spacer()
                Text(recovery.hasResumableCheckpoint() ? "Checkpoint Ready" : "Checkpoint Clear")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recovery.hasResumableCheckpoint() ? .orange : .green)
            }

            ppsrRow(label: "Metadata", value: lastSavedMetadataPath ?? "None", tint: .secondary)
            ppsrRow(label: "Screenshot", value: lastSavedProofPath ?? "None", tint: .secondary)
            ppsrRow(label: "Storage", value: String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB), tint: .blue)
            ppsrRow(label: "Recovery", value: recovery.diagnosticSummary, tint: recovery.hasResumableCheckpoint() ? .orange : .green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 14))
    }

    private func ppsrRow(label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private var selectedSite: AutomationSite? {
        AutomationSite(rawValue: selectedSiteID)
    }

    private var siteOptions: [DualFindSiteOption] {
        let presetOptions: [DualFindSiteOption] = AutomationSite.allCases.map {
            DualFindSiteOption(id: $0.rawValue, title: $0.displayName, symbolName: "globe")
        }
        return presetOptions + [DualFindSiteOption(id: "custom", title: "Custom", symbolName: "slider.horizontal.3")]
    }

    private var recommendedSelectors: [String] {
        guard let selectedSite else { return [] }
        return selectorFamily.selectors(for: selectedSite)
    }

    private var trimmedSelectorQuery: String {
        selectorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedURL: String {
        if let selectedSite {
            return settings.loginURL(for: selectedSite)
        }
        let trimmedValue: String = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                if let selectedSite {
                    return settings.loginURL(for: selectedSite)
                }
                return customURL
            },
            set: { newValue in
                if let selectedSite {
                    settings.setLoginURL(newValue, for: selectedSite)
                    settings.save()
                } else {
                    customURL = newValue
                }
            }
        )
    }

    private var proofImage: UIImage? {
        guard let proofImageData else { return nil }
        return UIImage(data: proofImageData)
    }

    private func syncSelection(forceSelectorRefresh: Bool) {
        if let selectedSite {
            if forceSelectorRefresh || selectorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectorQuery = selectorFamily.selectors(for: selectedSite).first ?? selectorQuery
            }
            if customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customURL = settings.loginURL(for: selectedSite)
            }
        } else if customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customURL = settings.joeURL
        }
    }

    private func performSearch() async {
        let targetURL: String = resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let selector: String = trimmedSelectorQuery
        guard !targetURL.isEmpty, !selector.isEmpty else { return }

        isSearching = true
        hasPerformedSearch = true
        results.removeAll()
        proofImageData = nil
        lastErrorMessage = nil
        lastRunSummary = nil

        do {
            if !orchestrator.isReady {
                try await orchestrator.startSession(speedMode: settings.speedMode)
            }

            let page: PlaywrightPage = try await orchestrator.newPage()
            defer {
                orchestrator.closePage(page)
            }

            try await page.goto(targetURL, waitUntil: .networkIdle)

            let locator: Locator = page.locator(selector)
            let count: Int = try await locator.count()
            var matches: [DualFindMatch] = []

            for index in 0..<min(count, 5) {
                let element: Locator = locator.nth(index)
                let textPreview: String = ((try? await element.textContent()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let placeholder: String? = try? await element.getAttribute("placeholder")
                let name: String? = try? await element.getAttribute("name")
                let idValue: String? = try? await element.getAttribute("id")
                let type: String? = try? await element.getAttribute("type")
                let isVisible: Bool = (try? await element.isVisible()) ?? false

                let attributes: [String] = [
                    idValue.map { "id=\($0)" },
                    name.map { "name=\($0)" },
                    type.map { "type=\($0)" },
                    placeholder.map { "placeholder=\($0)" }
                ].compactMap { $0 }

                matches.append(
                    DualFindMatch(
                        index: index + 1,
                        textPreview: textPreview.isEmpty ? "No text content" : String(textPreview.prefix(220)),
                        attributeSummary: attributes.isEmpty ? "No common attributes captured" : attributes.joined(separator: " • "),
                        isVisible: isVisible
                    )
                )
            }

            let screenshot: Data? = try? await page.screenshot()
            proofImageData = screenshot
            results = matches
            lastRunDate = Date()
            lastRunSummary = count == 1 ? "1 match found on \(page.url())" : "\(count) matches found on \(page.url())"

            let persistedPaths: (String?, String?) = persistArtifacts(
                url: targetURL,
                selector: selector,
                resolvedPageURL: page.url(),
                matches: matches,
                screenshot: screenshot
            )
            lastSavedMetadataPath = persistedPaths.0
            lastSavedProofPath = persistedPaths.1

            DebugLogger.shared.log(
                "Dual Find captured \(count) match(es) for \(selector) on \(targetURL)",
                category: .ppsr,
                level: .info
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            lastRunDate = Date()
            DebugLogger.shared.log(
                "Dual Find failed for \(selector) on \(targetURL): \(error.localizedDescription)",
                category: .ppsr,
                level: .error
            )
        }

        isSearching = false
    }

    private func persistArtifacts(
        url: String,
        selector: String,
        resolvedPageURL: String,
        matches: [DualFindMatch],
        screenshot: Data?
    ) -> (String?, String?) {
        let timestamp: String = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName: String = sanitized("dualfind_\((selectedSite?.rawValue ?? "custom"))_\(timestamp)")
        let metadataPath: String = "tools/dualfind/\(baseName).json"
        let screenshotPath: String? = screenshot == nil ? nil : "tools/dualfind/\(baseName).png"

        let artifact = DualFindArtifact(
            targetSite: selectedSite?.displayName ?? "Custom",
            searchURL: url,
            resolvedPageURL: resolvedPageURL,
            selectorFamily: selectorFamily.title,
            selector: selector,
            runTimestamp: Date(),
            matches: matches,
            screenshotPath: screenshotPath
        )

        if let metadata = try? JSONEncoder().encode(artifact) {
            PersistentFileStorageService.shared.save(data: metadata, filename: metadataPath)
        }

        if let screenshot, let screenshotPath {
            PersistentFileStorageService.shared.save(data: screenshot, filename: screenshotPath)
        }

        return (metadataPath, screenshotPath)
    }

    private func sanitized(_ value: String) -> String {
        let allowed: CharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces: [String] = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return pieces.isEmpty ? UUID().uuidString : pieces.joined(separator: "_")
    }
}

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
        case .username:
            return "Username"
        case .password:
            return "Password"
        case .submit:
            return "Submit"
        }
    }

    func selectors(for site: AutomationSite) -> [String] {
        switch self {
        case .username:
            return site.usernameSelectors
        case .password:
            return site.passwordSelectors
        case .submit:
            return site.submitSelectors
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
