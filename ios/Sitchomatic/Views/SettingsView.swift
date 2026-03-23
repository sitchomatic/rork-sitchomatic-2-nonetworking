import SwiftUI

struct SettingsView: View {
    @State private var settings = AutomationSettings.shared
    @State private var networkManager = SimpleNetworkManager.shared
    @State private var showClearConfirm: Bool = false
    @State private var showResetNetworkConfirm: Bool = false
    @State private var showResetMemoryConfirm: Bool = false
    @State private var showResetWebViewConfirm: Bool = false
    @State private var wireGuardAccessKey: String = ""
    @State private var wireGuardKeyError: String?
    @State private var isMeasuringLatency: Bool = false
    @State private var isRunningHealthCheck: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsWireGuardSection(
                    wireGuardAccessKey: $wireGuardAccessKey,
                    wireGuardKeyError: $wireGuardKeyError
                )
                SettingsSpeedModeSection(settings: settings)
                SettingsConcurrencySection(settings: settings)
                SettingsTimingOverridesSection(settings: settings)
                SettingsWebViewPoolSection(
                    settings: settings,
                    showResetConfirm: $showResetWebViewConfirm
                )
                SettingsStealthSection(settings: settings)
                SettingsMemoryProtectionSection(
                    settings: settings,
                    showResetConfirm: $showResetMemoryConfirm
                )
                SettingsNetworkConnectionSection(
                    networkManager: networkManager,
                    hasStoredKey: hasStoredWireGuardAccessKey,
                    isMeasuringLatency: $isMeasuringLatency
                )
                SettingsNetworkConfigSection(
                    settings: settings,
                    networkManager: networkManager,
                    showResetConfirm: $showResetNetworkConfirm
                )
                SettingsProxyManagementSection(
                    settings: settings,
                    networkManager: networkManager,
                    isRunningHealthCheck: $isRunningHealthCheck
                )
                SettingsDNSSection(settings: settings)
                SettingsLoggingSection(settings: settings)
                SettingsSiteURLsSection(settings: settings)
                settingsStorageSection
                settingsAboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadStoredWireGuardAccessKey() }
        .alert("Clear All Data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                PersistenceService.shared.clearAll()
                PersistentFileStorageService.shared.purgeAll()
            }
        } message: {
            Text("This will delete all credentials, attempts, and stored files.")
        }
        .alert("Reset Network Settings?", isPresented: $showResetNetworkConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { settings.resetNetworkDefaults() }
        } message: {
            Text("Timeouts, DNS, isolation, and reconnect settings will return to defaults.")
        }
        .alert("Reset Memory Thresholds?", isPresented: $showResetMemoryConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { settings.resetMemoryDefaults() }
        } message: {
            Text("All memory thresholds and cooldown settings will return to defaults.")
        }
        .alert("Reset WebView Settings?", isPresented: $showResetWebViewConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { settings.resetWebViewDefaults() }
        } message: {
            Text("Hard cap, stale timeout, pre-warm, and wipe settings will return to defaults.")
        }
    }

    private var settingsStorageSection: some View {
        NeonSettingsCard(title: "Storage", icon: "externaldrive") {
            NeonSettingsRow(label: "Storage Used") {
                Text(String(format: "%.1f MB", PersistentFileStorageService.shared.storageSizeMB))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }
            NeonSettingsRow(label: "WebView Budget") {
                Text(WebViewLifetimeBudgetService.shared.diagnosticSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            NeonDestructiveButton(title: "Clear All Data") {
                showClearConfirm = true
            }
        }
    }

    private var settingsAboutSection: some View {
        NeonSettingsCard(title: "About", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sitchomatic v16 Playwright Edition")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonGreen)
                Text("Permanent Dual Mode | Site profiles ready for expansion")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
            }
        }
    }

    private var hasStoredWireGuardAccessKey: Bool {
        !wireGuardAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadStoredWireGuardAccessKey() {
        do {
            wireGuardAccessKey = try WireGuardAccessKeyStore.load() ?? ""
            wireGuardKeyError = nil
        } catch {
            wireGuardAccessKey = ""
            wireGuardKeyError = "Unable to read the stored access key"
        }
    }
}

// MARK: - Shared Settings Components

struct NeonSettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(NeonTheme.neonCyan)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }
}

struct NeonSettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NeonTheme.textSecondary)
            Spacer()
            trailing
        }
    }
}

struct NeonDestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NeonTheme.neonRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(NeonTheme.neonRed.opacity(0.08), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonRed.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct NeonToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NeonTheme.textSecondary)
        }
        .tint(NeonTheme.neonGreen)
    }
}

struct NeonSliderRow: View {
    let label: String
    let valueText: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Slider(value: $value, in: range, step: step)
                .tint(color)
        }
    }
}

// MARK: - WireGuard

struct SettingsWireGuardSection: View {
    @Binding var wireGuardAccessKey: String
    @Binding var wireGuardKeyError: String?

    private var trimmed: String {
        wireGuardAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasKey: Bool { !trimmed.isEmpty }

    var body: some View {
        NeonSettingsCard(title: "WireGuard", icon: "lock.shield") {
            VStack(spacing: 10) {
                SecureField("Single access key", text: $wireGuardAccessKey)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(NeonTheme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.cardBorder, lineWidth: 0.5))

                NeonSettingsRow(label: "Status") {
                    HStack(spacing: 4) {
                        Image(systemName: hasKey ? "lock.shield.fill" : "shield.slash.fill")
                            .font(.system(size: 10))
                        Text(hasKey ? "Configured" : "Missing")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(hasKey ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                }

                Button {
                    saveKey()
                } label: {
                    Text("Save Securely")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(NeonTheme.neonGreen, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.4 : 1)

                if hasKey {
                    NeonDestructiveButton(title: "Clear Stored Key") { clearKey() }
                }

                if let wireGuardKeyError {
                    Text(wireGuardKeyError)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeonTheme.neonRed)
                }
            }

            Text("A single access key is kept in the device Keychain and reused across WireGuard tunnel sessions.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
    }

    private func saveKey() {
        do {
            try WireGuardAccessKeyStore.save(trimmed)
            wireGuardAccessKey = trimmed
            wireGuardKeyError = nil
        } catch {
            wireGuardKeyError = "Unable to save the access key securely"
        }
    }

    private func clearKey() {
        do {
            try WireGuardAccessKeyStore.delete()
            wireGuardAccessKey = ""
            wireGuardKeyError = nil
        } catch {
            wireGuardKeyError = "Unable to clear the stored access key"
        }
    }
}

// MARK: - Speed Mode

struct SettingsSpeedModeSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Speed Mode", icon: "gauge.with.dots.needle.50percent") {
            ForEach(SpeedMode.allCases, id: \.self) { mode in
                Button {
                    settings.speedMode = mode
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(settings.speedMode == mode ? NeonTheme.neonGreen : NeonTheme.textTertiary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(settings.speedMode == mode ? NeonTheme.textPrimary : NeonTheme.textSecondary)
                            Text(mode.description)
                                .font(.system(size: 9))
                                .foregroundStyle(NeonTheme.textTertiary)
                        }

                        Spacer()

                        if settings.speedMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(NeonTheme.neonGreen)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(settings.speedMode == mode ? NeonTheme.neonGreen.opacity(0.06) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(settings.speedMode == mode ? NeonTheme.neonGreen.opacity(0.2) : Color.clear, lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Typing: \(settings.speedMode.typingDelayMs)ms | Action: \(settings.speedMode.actionDelayMs)ms | Post-Submit: \(settings.speedMode.postSubmitWaitMs)ms")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.speedMode) { _, _ in settings.save() }
    }
}

// MARK: - Concurrency

struct SettingsConcurrencySection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Concurrency", icon: "arrow.triangle.branch") {
            HStack {
                Text("Max Concurrent Pairs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.maxConcurrentPairs)", value: $settings.maxConcurrentPairs, in: 1...12)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            HStack {
                Text("Max Retry Attempts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.maxRetryAttempts)", value: $settings.maxRetryAttempts, in: 0...10)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            NeonToggle(label: "Auto-Retry on Failure", isOn: $settings.autoRetryOnFailure)

            NeonSliderRow(
                label: "Inter-Wave Delay",
                valueText: String(format: "%.1fs", settings.interWaveDelaySeconds),
                color: NeonTheme.neonCyan,
                value: $settings.interWaveDelaySeconds,
                range: 0...15,
                step: 0.5
            )
        }
        .onChange(of: settings.maxConcurrentPairs) { _, _ in settings.save() }
        .onChange(of: settings.maxRetryAttempts) { _, _ in settings.save() }
        .onChange(of: settings.autoRetryOnFailure) { _, _ in settings.save() }
        .onChange(of: settings.interWaveDelaySeconds) { _, _ in settings.save() }
    }
}

// MARK: - Timing Overrides

struct SettingsTimingOverridesSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Timing Overrides", icon: "timer") {
            NeonSliderRow(
                label: "Navigation Timeout",
                valueText: settings.navigationTimeoutOverride > 0 ? String(format: "%.0fs", settings.navigationTimeoutOverride) : "Auto (\(String(format: "%.0fs", settings.speedMode.navigationTimeoutSeconds)))",
                color: NeonTheme.neonOrange,
                value: $settings.navigationTimeoutOverride,
                range: 0...120,
                step: 5
            )

            NeonSliderRow(
                label: "Selector Timeout",
                valueText: settings.selectorTimeoutOverride > 0 ? String(format: "%.0fs", settings.selectorTimeoutOverride) : "Auto (\(String(format: "%.0fs", settings.speedMode.selectorTimeoutSeconds)))",
                color: NeonTheme.neonOrange,
                value: $settings.selectorTimeoutOverride,
                range: 0...60,
                step: 1
            )

            Text("Set to 0 to use speed mode defaults. Override for sites with slow load times.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.navigationTimeoutOverride) { _, _ in settings.save() }
        .onChange(of: settings.selectorTimeoutOverride) { _, _ in settings.save() }
    }
}

// MARK: - WebView Pool

struct SettingsWebViewPoolSection: View {
    @Bindable var settings: AutomationSettings
    @Binding var showResetConfirm: Bool

    var body: some View {
        NeonSettingsCard(title: "WebView Pool", icon: "square.stack.3d.up") {
            HStack {
                Text("Hard Cap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.webViewHardCap)", value: $settings.webViewHardCap, in: 4...48)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            HStack {
                Text("Stale Timeout")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.staleSessionTimeoutSeconds)s", value: $settings.staleSessionTimeoutSeconds, in: 60...900, step: 30)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            HStack {
                Text("Pre-Warm Count")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.preWarmCount)", value: $settings.preWarmCount, in: 0...6)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            NeonToggle(label: "Wipe Data on Release", isOn: $settings.wipeDataOnRelease)
            NeonToggle(label: "User Agent Rotation", isOn: $settings.userAgentRotation)

            NeonSettingsRow(label: "Pool Status") {
                Text(WebViewPool.shared.diagnosticSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            NeonDestructiveButton(title: "Reset WebView Defaults") {
                showResetConfirm = true
            }

            Text("Controls WebView lifecycle, isolation, and memory footprint.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.webViewHardCap) { _, _ in settings.save() }
        .onChange(of: settings.staleSessionTimeoutSeconds) { _, _ in settings.save() }
        .onChange(of: settings.preWarmCount) { _, _ in settings.save() }
        .onChange(of: settings.wipeDataOnRelease) { _, _ in settings.save() }
        .onChange(of: settings.userAgentRotation) { _, _ in settings.save() }
    }
}

// MARK: - Stealth & Debugging

struct SettingsStealthSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Stealth & Debugging", icon: "eye.slash") {
            NeonToggle(label: "Stealth Mode", isOn: $settings.stealthEnabled)
            NeonToggle(label: "Fingerprint Rotation", isOn: $settings.fingerprintRotation)
            NeonToggle(label: "Enable Tracing", isOn: $settings.enableTracing)
            NeonToggle(label: "Screenshots on Failure", isOn: $settings.captureScreenshotsOnFailure)
        }
        .onChange(of: settings.stealthEnabled) { _, _ in settings.save() }
        .onChange(of: settings.fingerprintRotation) { _, _ in settings.save() }
        .onChange(of: settings.enableTracing) { _, _ in settings.save() }
        .onChange(of: settings.captureScreenshotsOnFailure) { _, _ in settings.save() }
    }
}

// MARK: - Memory Protection

struct SettingsMemoryProtectionSection: View {
    @Bindable var settings: AutomationSettings
    @Binding var showResetConfirm: Bool

    var body: some View {
        NeonSettingsCard(title: "Memory Protection", icon: "memorychip") {
            memorySlider(label: "Safe Threshold", value: settings.memorySafeThresholdMB, range: 200...800, color: NeonTheme.neonGreen) {
                settings.memorySafeThresholdMB = $0
            }
            memorySlider(label: "Elevated Threshold", value: settings.memoryElevatedThresholdMB, range: 300...900, color: NeonTheme.neonYellow) {
                settings.memoryElevatedThresholdMB = $0
            }
            memorySlider(label: "Critical Threshold", value: settings.memoryCriticalThresholdMB, range: 400...1200, color: NeonTheme.neonOrange) {
                settings.memoryCriticalThresholdMB = $0
            }
            memorySlider(label: "Emergency Threshold", value: settings.memoryEmergencyThresholdMB, range: 600...1500, color: NeonTheme.neonRed) {
                settings.memoryEmergencyThresholdMB = $0
            }

            NeonSliderRow(
                label: "Cooldown Duration",
                valueText: String(format: "%.1fs", settings.cooldownBaseDuration),
                color: NeonTheme.neonCyan,
                value: $settings.cooldownBaseDuration,
                range: 1...30,
                step: 0.5
            )

            NeonSettingsRow(label: "Current") {
                Text(CrashProtectionService.shared.diagnosticSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            NeonDestructiveButton(title: "Reset Memory Defaults") {
                showResetConfirm = true
            }

            Text("Thresholds auto-reduce after each crash. Lower values = earlier intervention.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.memorySafeThresholdMB) { _, _ in settings.save() }
        .onChange(of: settings.memoryElevatedThresholdMB) { _, _ in settings.save() }
        .onChange(of: settings.memoryCriticalThresholdMB) { _, _ in settings.save() }
        .onChange(of: settings.memoryEmergencyThresholdMB) { _, _ in settings.save() }
        .onChange(of: settings.cooldownBaseDuration) { _, _ in settings.save() }
    }

    private func memorySlider(label: String, value: Int, range: ClosedRange<Double>, color: Color, setter: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Text("\(value) MB")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { setter(Int($0)) }
            ), in: range, step: 25)
            .tint(color)
        }
    }
}

// MARK: - Network Connection

struct SettingsNetworkConnectionSection: View {
    @Bindable var networkManager: SimpleNetworkManager
    let hasStoredKey: Bool
    @Binding var isMeasuringLatency: Bool

    var body: some View {
        NeonSettingsCard(title: "Network", icon: "network") {
            NeonSettingsRow(label: "Status") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(networkManager.connectionStatus == .connected ? NeonTheme.neonGreen : NeonTheme.neonRed)
                        .frame(width: 6, height: 6)
                        .neonGlow(networkManager.connectionStatus == .connected ? NeonTheme.neonGreen : NeonTheme.neonRed, radius: 2)
                    Text(networkManager.connectionStatus.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(networkManager.connectionStatus == .connected ? NeonTheme.neonGreen : NeonTheme.neonRed)
                }
            }

            NeonSettingsRow(label: "Proxies") {
                Text("\(networkManager.proxyCount)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }

            NeonSettingsRow(label: "Access Key") {
                Text(hasStoredKey ? "Single-Key Ready" : "Not Set")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hasStoredKey ? NeonTheme.neonGreen : NeonTheme.textTertiary)
            }

            if networkManager.lastLatencyMs != 0 {
                NeonSettingsRow(label: "Latency") {
                    Text(latencyLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latencyColor)
                }
            }

            HStack(spacing: 8) {
                if networkManager.connectionStatus == .disconnected {
                    Button {
                        Task { await networkManager.connect() }
                    } label: {
                        Text("Connect")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(NeonTheme.neonGreen, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        networkManager.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NeonTheme.neonRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(NeonTheme.neonRed.opacity(0.08), in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonRed.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isMeasuringLatency = true
                    Task {
                        await networkManager.measureLatency()
                        isMeasuringLatency = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isMeasuringLatency {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(NeonTheme.neonCyan)
                        }
                        Text("Ping")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(NeonTheme.neonCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(NeonTheme.neonCyan.opacity(0.08), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonCyan.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(isMeasuringLatency)
            }
        }
    }

    private var latencyLabel: String {
        networkManager.lastLatencyMs > 0 ? "\(networkManager.lastLatencyMs) ms" : "Failed"
    }

    private var latencyColor: Color {
        if networkManager.lastLatencyMs <= 0 { return NeonTheme.neonRed }
        return networkManager.lastLatencyMs < 200 ? NeonTheme.neonGreen : NeonTheme.neonOrange
    }
}

// MARK: - Network Configuration

struct SettingsNetworkConfigSection: View {
    @Bindable var settings: AutomationSettings
    @Bindable var networkManager: SimpleNetworkManager
    @Binding var showResetConfirm: Bool

    var body: some View {
        NeonSettingsCard(title: "Network Configuration", icon: "gearshape.2") {
            NeonSliderRow(
                label: "Connection Timeout",
                valueText: String(format: "%.0fs", settings.connectionTimeoutSeconds),
                color: NeonTheme.neonCyan,
                value: $settings.connectionTimeoutSeconds,
                range: 5...120,
                step: 5
            )

            NeonSliderRow(
                label: "Request Timeout",
                valueText: String(format: "%.0fs", settings.requestTimeoutSeconds),
                color: NeonTheme.neonCyan,
                value: $settings.requestTimeoutSeconds,
                range: 10...300,
                step: 10
            )

            NeonToggle(label: "Strict Network Isolation", isOn: $settings.networkIsolationStrict)
            NeonToggle(label: "Auto-Reconnect", isOn: $settings.autoReconnect)

            HStack {
                Text("Max Retries")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.maxNetworkRetries)", value: $settings.maxNetworkRetries, in: 0...10)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            NeonToggle(label: "Bandwidth Monitoring", isOn: $settings.bandwidthMonitoring)

            if settings.bandwidthMonitoring {
                NeonSettingsRow(label: "Bandwidth") {
                    Text(networkManager.bandwidthSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
                Button {
                    networkManager.resetBandwidthCounters()
                } label: {
                    Text("Reset Counters")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NeonTheme.neonCyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(NeonTheme.neonCyan.opacity(0.08), in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonCyan.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            NeonDestructiveButton(title: "Reset Network Defaults") {
                showResetConfirm = true
            }

            Text("Strict isolation uses separate WebKit data stores per session.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.connectionTimeoutSeconds) { _, _ in settings.save() }
        .onChange(of: settings.requestTimeoutSeconds) { _, _ in settings.save() }
        .onChange(of: settings.networkIsolationStrict) { _, _ in settings.save() }
        .onChange(of: settings.autoReconnect) { _, _ in settings.save() }
        .onChange(of: settings.maxNetworkRetries) { _, _ in settings.save() }
        .onChange(of: settings.bandwidthMonitoring) { _, _ in settings.save() }
    }
}

// MARK: - Proxy Management

struct SettingsProxyManagementSection: View {
    @Bindable var settings: AutomationSettings
    @Bindable var networkManager: SimpleNetworkManager
    @Binding var isRunningHealthCheck: Bool

    var body: some View {
        NeonSettingsCard(title: "Proxy Management", icon: "arrow.triangle.swap") {
            NeonToggle(label: "Health Check on Connect", isOn: $settings.proxyHealthCheckOnConnect)

            HStack {
                Text("Rotation Interval")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper(
                    settings.proxyRotationIntervalSeconds > 0 ? "\(settings.proxyRotationIntervalSeconds)s" : "Off",
                    value: $settings.proxyRotationIntervalSeconds,
                    in: 0...600,
                    step: 30
                )
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(NeonTheme.neonCyan)
            }

            if !networkManager.proxyHealthStatus.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(networkManager.proxyHealthStatus.sorted(by: { $0.key < $1.key })), id: \.key) { key, health in
                        HStack(spacing: 8) {
                            Image(systemName: health.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(proxyHealthColor(for: health))
                            Text(key)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(NeonTheme.textSecondary)
                            Spacer()
                            Text(health.displayName)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(proxyHealthColor(for: health))
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02), in: .rect(cornerRadius: 10))
            }

            Button {
                isRunningHealthCheck = true
                Task {
                    await networkManager.runProxyHealthChecks()
                    isRunningHealthCheck = false
                }
            } label: {
                HStack(spacing: 4) {
                    if isRunningHealthCheck {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(NeonTheme.neonCyan)
                    }
                    Text("Run Health Check")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(NeonTheme.neonCyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(NeonTheme.neonCyan.opacity(0.08), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonCyan.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(isRunningHealthCheck || networkManager.proxyCount == 0)
            .opacity(isRunningHealthCheck || networkManager.proxyCount == 0 ? 0.4 : 1)

            NeonSettingsRow(label: "Healthy") {
                Text("\(networkManager.healthyProxyCount)/\(networkManager.proxyCount)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonGreen)
            }

            Text("Set rotation to 0 to disable auto proxy cycling.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.proxyHealthCheckOnConnect) { _, _ in settings.save() }
        .onChange(of: settings.proxyRotationIntervalSeconds) { _, _ in settings.save() }
    }

    private func proxyHealthColor(for health: ProxyHealth) -> Color {
        switch health {
        case .healthy: NeonTheme.neonGreen
        case .degraded: NeonTheme.neonOrange
        case .unreachable: NeonTheme.neonRed
        }
    }
}

// MARK: - DNS

struct SettingsDNSSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "DNS", icon: "globe") {
            HStack {
                Text("Provider")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Picker("", selection: $settings.dnsPreference) {
                    ForEach(DNSPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.menu)
                .tint(NeonTheme.neonCyan)
            }

            if settings.dnsPreference != .system {
                NeonSettingsRow(label: "Primary") {
                    Text(settings.dnsPreference.primaryAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                NeonSettingsRow(label: "Secondary") {
                    Text(settings.dnsPreference.secondaryAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(NeonTheme.textSecondary)
                }
            }

            Text("DNS preference applies to WireGuard tunnel configurations.")
                .font(.system(size: 9))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .onChange(of: settings.dnsPreference) { _, _ in settings.save() }
    }
}

// MARK: - Logging

struct SettingsLoggingSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Logging", icon: "doc.text") {
            HStack {
                Text("Min Log Level")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Picker("", selection: $settings.minimumLogLevel) {
                    ForEach(DebugLogger.LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.title).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(NeonTheme.neonCyan)
            }

            HStack {
                Text("Retention Limit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeonTheme.textSecondary)
                Spacer()
                Stepper("\(settings.logRetentionLimit)", value: $settings.logRetentionLimit, in: 500...20000, step: 500)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeonTheme.neonCyan)
            }

            NeonSettingsRow(label: "Current Entries") {
                Text("\(DebugLogger.shared.entries.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeonTheme.textSecondary)
            }

            Button {
                DebugLogger.shared.clear()
            } label: {
                Text("Clear Log Buffer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NeonTheme.neonOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(NeonTheme.neonOrange.opacity(0.08), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonOrange.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .onChange(of: settings.minimumLogLevel) { _, _ in settings.save() }
        .onChange(of: settings.logRetentionLimit) { _, _ in settings.save() }
    }
}

// MARK: - Site URLs

struct SettingsSiteURLsSection: View {
    @Bindable var settings: AutomationSettings

    var body: some View {
        NeonSettingsCard(title: "Site URLs", icon: "link") {
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

            Button {
                settings.resetLoginURLsToDefaults()
            } label: {
                Text("Reset Default URLs")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NeonTheme.neonOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(NeonTheme.neonOrange.opacity(0.08), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.neonOrange.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .onChange(of: settings.joeURL) { _, _ in settings.save() }
        .onChange(of: settings.ignitionURL) { _, _ in settings.save() }
    }

    private func siteURLBinding(for site: AutomationSite) -> Binding<String> {
        Binding(
            get: { settings.loginURL(for: site) },
            set: { settings.setLoginURL($0, for: site) }
        )
    }

    private func primarySelectorSummary(for site: AutomationSite) -> String {
        let u: String = site.usernameSelectors.first ?? "n/a"
        let p: String = site.passwordSelectors.first ?? "n/a"
        let s: String = site.submitSelectors.first ?? "n/a"
        return "Selectors: \(u) \u{2022} \(p) \u{2022} \(s)"
    }
}
