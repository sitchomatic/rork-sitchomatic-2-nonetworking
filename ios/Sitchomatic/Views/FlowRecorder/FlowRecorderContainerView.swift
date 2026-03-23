import SwiftUI
import UIKit

struct FlowRecorderContainerView: View {
    @State private var recorder: RecordingSession = RecordingSession()
    @State private var engine: ConcurrentAutomationEngine = .shared
    @State private var settings: AutomationSettings = .shared
    @State private var recovery: SessionRecoveryService = .shared
    @State private var selectedSiteID: String = AutomationSite.joe.rawValue
    @State private var customURL: String = ""
    @State private var previewSessions: Int = 1
    @State private var previewConcurrency: Int = 1
    @State private var showGeneratedCode: Bool = true
    @State private var lastSavedCodePath: String?
    @State private var lastSavedManifestPath: String?
    @State private var saveStatusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewCard
                compositionCard
                quickInsertCard
                actionsCard
                if showGeneratedCode {
                    generatedCodeCard
                }
                ppsrCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Flow Recorder")
        .navigationBarTitleDisplayMode(.large)
        .task {
            syncSelection()
        }
        .onChange(of: selectedSiteID) { _, _ in
            syncSelection()
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recorded Script Studio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Text("Compose login flows, export Swift, and fire a recorded preview run.")
                        .font(.title3.weight(.bold))
                    Text("Section 5 closes the loop between tool authoring, the recorded-run engine, and PPSR artifact persistence.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Label(recorderStatusTitle, systemImage: recorderStatusSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(recorderStatusColor)
                    Text(engine.state.displayName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                statPill(title: "Actions", value: "\(recorder.actionCount)", tint: .cyan)
                statPill(title: "Mode", value: recorder.mode.displayName, tint: .blue)
                statPill(title: "Preview", value: engine.state.displayName, tint: engine.state.isActive ? .orange : .green)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Composition")
                    .font(.headline)
                Spacer()
                if let saveStatusMessage {
                    Text(saveStatusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

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
                Text("Target URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("https://example.com/login", text: urlBinding)
                    .font(.footnote.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recorder mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RecorderMode.allCases, id: \.self) { mode in
                            Button {
                                recorder.mode = mode
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.iconName)
                                    Text(mode.displayName)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(recorder.mode == mode ? .blue.opacity(0.16) : .secondary.opacity(0.08), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(recorder.mode == mode ? .blue : .secondary)
                        }
                    }
                    .contentMargins(.horizontal, 0)
                }
            }

            HStack(spacing: 10) {
                controlButton(title: recorder.isRecording ? "Stop" : "Start", systemImage: recorder.isRecording ? "stop.fill" : "record.circle.fill", tint: recorder.isRecording ? .red : .cyan) {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                }

                controlButton(title: recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill", tint: .orange) {
                    if recorder.isPaused {
                        recorder.resumeRecording()
                    } else {
                        recorder.pauseRecording()
                    }
                }
                .disabled(!recorder.isRecording)

                controlButton(title: "Undo", systemImage: "arrow.uturn.backward", tint: .secondary) {
                    recorder.removeLastAction()
                }
                .disabled(recorder.actions.isEmpty)

                controlButton(title: "Clear", systemImage: "trash", tint: .red) {
                    recorder.clearActions()
                }
                .disabled(recorder.actions.isEmpty)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var quickInsertCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Inserts")
                    .font(.headline)
                Spacer()
                Text(selectedSite?.displayName ?? "Custom")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: quickInsertColumns, spacing: 10) {
                quickInsertButton(title: "Navigate", symbol: "globe") {
                    appendQuickAction(.navigation)
                }
                quickInsertButton(title: "Username", symbol: "person.crop.circle") {
                    appendQuickAction(.usernameFill)
                }
                quickInsertButton(title: "Password", symbol: "key.fill") {
                    appendQuickAction(.passwordFill)
                }
                quickInsertButton(title: "Submit", symbol: "arrow.up.circle.fill") {
                    appendQuickAction(.submit)
                }
                quickInsertButton(title: "Assert", symbol: "checkmark.shield.fill") {
                    appendQuickAction(.assertSuccess)
                }
                quickInsertButton(title: "Wait", symbol: "clock.arrow.circlepath") {
                    appendQuickAction(.wait)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recorded Actions")
                    .font(.headline)
                Spacer()
                Button {
                    showGeneratedCode.toggle()
                } label: {
                    Label(showGeneratedCode ? "Hide Code" : "Show Code", systemImage: showGeneratedCode ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            if recorder.actions.isEmpty {
                ContentUnavailableView(
                    "No Actions Yet",
                    systemImage: "record.circle",
                    description: Text("Use the quick inserts to scaffold Joe or Ignition flows, then export or run a preview.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(recorder.actions.enumerated()), id: \.element.id) { index, action in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)

                            Image(systemName: action.iconName)
                                .foregroundStyle(.cyan)
                                .frame(width: 18)

                            Text(action.displayDescription)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
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

    private var generatedCodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated Swift")
                        .font(.headline)
                    Text("Exportable Playwright-style Swift for the recorded flow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lastSavedCodePath {
                    Text(lastSavedCodePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(recorder.generatedCode)
                .font(.footnote.monospaced())
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.black, in: .rect(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Stepper("Sessions: \(previewSessions)", value: $previewSessions, in: 1...3)
                    Stepper("Concurrency: \(previewConcurrency)", value: $previewConcurrency, in: 1...3)
                }
                .font(.caption)
            }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = recorder.generatedCode
                    saveStatusMessage = "Copied"
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    saveScriptArtifacts()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(recorder.actions.isEmpty)

                Button {
                    runPreview()
                } label: {
                    Label(engine.state.isActive ? "Previewing" : "Run Preview", systemImage: engine.state.isActive ? "hourglass" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(recorder.actions.isEmpty || engine.state.isActive)
            }

            if engine.state.isActive || engine.state == .completed || engine.state == .failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Engine status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(engine.engineDiagnostics)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(NeonTheme.cardBackground, in: .rect(cornerRadius: 16))
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

            ppsrRow(label: "Manifest", value: lastSavedManifestPath ?? "None", tint: .secondary)
            ppsrRow(label: "Swift", value: lastSavedCodePath ?? "None", tint: .secondary)
            ppsrRow(label: "Storage", value: String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB), tint: .blue)
            ppsrRow(label: "Recovery", value: recovery.diagnosticSummary, tint: recovery.hasResumableCheckpoint() ? .orange : .green)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private var selectedSite: AutomationSite? {
        AutomationSite(rawValue: selectedSiteID)
    }

    private var resolvedURL: String {
        if let selectedSite {
            return settings.loginURL(for: selectedSite)
        }
        return customURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var siteOptions: [FlowRecorderSiteOption] {
        let presetOptions: [FlowRecorderSiteOption] = AutomationSite.allCases.map {
            FlowRecorderSiteOption(id: $0.rawValue, title: $0.displayName, symbolName: "globe")
        }
        return presetOptions + [FlowRecorderSiteOption(id: "custom", title: "Custom", symbolName: "slider.horizontal.3")]
    }

    private var quickInsertColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
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

    private var recorderStatusTitle: String {
        if recorder.isPaused {
            return "Paused"
        }
        if recorder.isRecording {
            return "Recording"
        }
        return "Idle"
    }

    private var recorderStatusSymbol: String {
        if recorder.isPaused {
            return "pause.circle.fill"
        }
        if recorder.isRecording {
            return "record.circle.fill"
        }
        return "circle"
    }

    private var recorderStatusColor: Color {
        if recorder.isPaused {
            return .orange
        }
        if recorder.isRecording {
            return .red
        }
        return .secondary
    }

    private func syncSelection() {
        if let selectedSite, customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customURL = settings.loginURL(for: selectedSite)
        }
    }

    private func controlButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func quickInsertButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(quickInsertDescription(title: title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(NeonTheme.cardBackground, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func quickInsertDescription(title: String) -> String {
        switch title {
        case "Navigate":
            return "Insert the selected login URL"
        case "Username":
            return "Fill the primary username selector"
        case "Password":
            return "Fill the primary password selector"
        case "Submit":
            return "Tap the primary submit selector"
        case "Assert":
            return "Check for a likely success signal"
        default:
            return "Wait for late DOM changes"
        }
    }

    private func appendQuickAction(_ quickAction: FlowRecorderQuickAction) {
        if !recorder.isRecording {
            recorder.startRecording()
        }
        if recorder.isPaused {
            recorder.resumeRecording()
        }

        let timestamp: Date = Date()

        switch quickAction {
        case .navigation:
            let targetURL: String = resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetURL.isEmpty else { return }
            recorder.addAction(RecordedAction(kind: .navigation, selector: nil, value: targetURL, timestamp: timestamp))

        case .usernameFill:
            let selector: String = selectedSite?.usernameSelectors.first ?? "input[name='username']"
            recorder.addAction(RecordedAction(kind: .fill, selector: selector, value: "YOUR_USERNAME", timestamp: timestamp))

        case .passwordFill:
            let selector: String = selectedSite?.passwordSelectors.first ?? "input[type='password']"
            recorder.addAction(RecordedAction(kind: .fill, selector: selector, value: "YOUR_PASSWORD", timestamp: timestamp))

        case .submit:
            let selector: String = selectedSite?.submitSelectors.first ?? "button[type='submit']"
            recorder.addAction(RecordedAction(kind: .click, selector: selector, value: nil, timestamp: timestamp))
            recorder.addAction(RecordedAction(kind: .waitForTimeout, selector: nil, value: "1500", timestamp: timestamp))

        case .assertSuccess:
            let successText: String = selectedSite?.successTextHints.first ?? "cashier"
            recorder.addAction(RecordedAction(kind: .assertText, selector: "body", value: successText, timestamp: timestamp))

        case .wait:
            recorder.addAction(RecordedAction(kind: .waitForTimeout, selector: nil, value: "1000", timestamp: timestamp))
        }
    }

    private func runPreview() {
        let scriptActions: [RecordedAction] = previewActions()
        guard !scriptActions.isEmpty else { return }

        let config = WaveConfig(
            concurrency: previewConcurrency,
            delayBetweenWaves: 1,
            targetURL: resolvedURL,
            script: .recorded(scriptActions),
            totalSessions: previewSessions,
            captureScreenshots: true
        )
        engine.startRecordedRun(config: config)
        saveStatusMessage = "Preview started"
        DebugLogger.shared.log(
            "Flow Recorder preview started with \(scriptActions.count) action(s)",
            category: .ppsr,
            level: .info
        )
    }

    private func previewActions() -> [RecordedAction] {
        let actions: [RecordedAction] = recorder.actions
        guard !actions.isEmpty else { return [] }

        let hasNavigation: Bool = actions.contains { $0.kind == .navigation }
        let targetURL: String = resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasNavigation, !targetURL.isEmpty else { return actions }

        let navigation = RecordedAction(kind: .navigation, selector: nil, value: targetURL, timestamp: Date())
        return [navigation] + actions
    }

    private func saveScriptArtifacts() {
        let actions: [RecordedAction] = previewActions()
        guard !actions.isEmpty else { return }

        let timestamp: String = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName: String = sanitized("recorder_\((selectedSite?.rawValue ?? "custom"))_\(timestamp)")
        let codePath: String = "tools/recorder/\(baseName).swift"
        let manifestPath: String = "tools/recorder/\(baseName).json"

        PersistentFileStorageService.shared.save(text: recorder.generatedCode, filename: codePath)

        let artifact = FlowRecorderArtifact(
            targetSite: selectedSite?.displayName ?? "Custom",
            targetURL: resolvedURL,
            mode: recorder.mode.displayName,
            actionCount: actions.count,
            savedAt: Date(),
            actions: actions,
            generatedCodePath: codePath
        )

        if let data = try? JSONEncoder().encode(artifact) {
            PersistentFileStorageService.shared.save(data: data, filename: manifestPath)
        }

        lastSavedCodePath = codePath
        lastSavedManifestPath = manifestPath
        saveStatusMessage = "Saved"
        DebugLogger.shared.log(
            "Flow Recorder artifacts saved to \(manifestPath)",
            category: .ppsr,
            level: .info
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

    private func sanitized(_ value: String) -> String {
        let allowed: CharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces: [String] = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return pieces.isEmpty ? UUID().uuidString : pieces.joined(separator: "_")
    }
}

nonisolated struct FlowRecorderSiteOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
}

nonisolated enum FlowRecorderQuickAction: Sendable {
    case navigation
    case usernameFill
    case passwordFill
    case submit
    case assertSuccess
    case wait
}

nonisolated struct FlowRecorderArtifact: Codable, Sendable {
    let targetSite: String
    let targetURL: String
    let mode: String
    let actionCount: Int
    let savedAt: Date
    let actions: [RecordedAction]
    let generatedCodePath: String
}
