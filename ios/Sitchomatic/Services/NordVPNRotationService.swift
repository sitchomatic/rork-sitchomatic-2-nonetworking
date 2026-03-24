import Foundation
import UIKit
import Network
import UserNotifications

nonisolated enum NordVPNRotationStrategy: String, Sendable, CaseIterable, Codable {
    case shortcutDisconnectReconnect
    case combinedShortcut
    case autoRotation
    case manualNotification

    var displayName: String {
        switch self {
        case .shortcutDisconnectReconnect: "Disconnect / Reconnect"
        case .combinedShortcut: "Combined Rotate"
        case .autoRotation: "Auto Rotation"
        case .manualNotification: "Manual Notification"
        }
    }

    var description: String {
        switch self {
        case .shortcutDisconnectReconnect: "Two-step: disconnect then reconnect via separate Shortcuts"
        case .combinedShortcut: "Single shortcut handles full rotation (fewest app switches)"
        case .autoRotation: "Auto-triggers rotation shortcut post-wave on detection"
        case .manualNotification: "Sends a notification — you rotate NordVPN manually"
        }
    }

    var iconName: String {
        switch self {
        case .shortcutDisconnectReconnect: "arrow.triangle.2.circlepath"
        case .combinedShortcut: "bolt.shield"
        case .autoRotation: "gearshape.arrow.triangle.2.circlepath"
        case .manualNotification: "bell.badge"
        }
    }
}

nonisolated enum NordVPNTriggerReason: String, Sendable {
    case permDisabledDetected
    case fingerprintingDetected
    case highFailureRate
    case manualRequest

    var notificationBody: String {
        switch self {
        case .permDisabledDetected: "Permanently disabled account detected — rotate your NordVPN server now."
        case .fingerprintingDetected: "Fingerprinting symptoms detected — rotate your NordVPN server to refresh your IP."
        case .highFailureRate: "High failure rate this wave — consider rotating your NordVPN server."
        case .manualRequest: "NordVPN rotation requested."
        }
    }
}

nonisolated enum VPNVerificationState: String, Sendable {
    case idle
    case waitingForDisconnect
    case waitingForReconnect
    case verifyingIPChange
    case confirmed
    case failed
    case timedOut
}

@Observable
@MainActor
final class NordVPNRotationService {
    static let shared = NordVPNRotationService()

    private(set) var lastRotationDate: Date?
    private(set) var rotationCount: Int = 0
    private(set) var lastTriggerReason: NordVPNTriggerReason?
    private(set) var isRotating: Bool = false
    private(set) var lastError: String?
    private(set) var verificationState: VPNVerificationState = .idle
    private(set) var lastKnownIP: String?
    private(set) var lastVerifiedIP: String?
    private(set) var ipChanged: Bool = false
    private(set) var networkPathSatisfied: Bool = true
    private(set) var shortcutCallbackReceived: Bool = false

    var disconnectShortcutName: String = "NordVPN Disconnect"
    var reconnectShortcutName: String = "NordVPN Quick Connect"
    var rotateShortcutName: String = "NordVPN Rotate Server"
    var combinedShortcutName: String = "NordVPN Rotate"

    var shortcutDisconnectReconnectEnabled: Bool = true
    var combinedShortcutEnabled: Bool = false
    var autoRotationEnabled: Bool = false
    var manualNotificationEnabled: Bool = true

    var cooldownSeconds: Double = 10.0
    var verifyIPChange: Bool = true
    var adaptiveTimeoutSeconds: Double = 15.0
    var useCallbackURL: Bool = true

    private let logger = DebugLogger.shared
    private let haptics = HapticService.shared
    private var lastRotationTime: Date = .distantPast
    private var pathMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "sitchomatic.nwpathmonitor")
    private var callbackContinuation: CheckedContinuation<Bool, Never>?

    private let persistenceKey = "sitchomatic.nordvpn.settings.v2"
    private let ipCheckURL = "https://api.ipify.org?format=text"

    private init() {
        load()
        requestNotificationPermission()
        startPathMonitor()
    }

    var isOnCooldown: Bool {
        Date().timeIntervalSince(lastRotationTime) < cooldownSeconds
    }

    var cooldownRemaining: TimeInterval {
        max(0, cooldownSeconds - Date().timeIntervalSince(lastRotationTime))
    }

    var activeStrategyName: String {
        if combinedShortcutEnabled { return NordVPNRotationStrategy.combinedShortcut.displayName }
        if shortcutDisconnectReconnectEnabled { return NordVPNRotationStrategy.shortcutDisconnectReconnect.displayName }
        if autoRotationEnabled { return NordVPNRotationStrategy.autoRotation.displayName }
        if manualNotificationEnabled { return NordVPNRotationStrategy.manualNotification.displayName }
        return "None"
    }

    var diagnosticSummary: String {
        let lastRotation = lastRotationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "Never"
        let ipInfo = lastVerifiedIP ?? "Unknown"
        return "Strategy: \(activeStrategyName) | Rotations: \(rotationCount) | Last: \(lastRotation) | IP: \(ipInfo) | Net: \(networkPathSatisfied ? "OK" : "DOWN")"
    }

    // MARK: - Path Monitor

    private func startPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                if self.networkPathSatisfied != satisfied {
                    self.networkPathSatisfied = satisfied
                    self.logger.log("[NordVPN] Network path: \(satisfied ? "satisfied" : "unsatisfied")", category: .network, level: .info)
                }
            }
        }
        pathMonitor?.start(queue: monitorQueue)
    }

    // MARK: - x-callback-url Handler

    func handleCallbackURL(_ url: URL) {
        guard let host = url.host else { return }

        switch host {
        case "vpn-rotated":
            logger.log("[NordVPN] Callback received: vpn-rotated", category: .network, level: .info)
            shortcutCallbackReceived = true
            callbackContinuation?.resume(returning: true)
            callbackContinuation = nil
        case "vpn-error":
            let errorMsg = url.queryValue(for: "message") ?? "Unknown error"
            logger.log("[NordVPN] Callback received: vpn-error — \(errorMsg)", category: .network, level: .error)
            shortcutCallbackReceived = true
            callbackContinuation?.resume(returning: false)
            callbackContinuation = nil
        default:
            break
        }
    }

    // MARK: - Rotation

    func triggerRotation(reason: NordVPNTriggerReason) async {
        guard !isRotating else {
            logger.log("[NordVPN] Already rotating — skipping", category: .network, level: .warning)
            return
        }

        guard !isOnCooldown else {
            logger.log("[NordVPN] On cooldown (\(String(format: "%.0f", cooldownRemaining))s remaining) — skipping", category: .network, level: .info)
            return
        }

        lastTriggerReason = reason
        isRotating = true
        lastError = nil
        ipChanged = false
        shortcutCallbackReceived = false

        logger.log("[NordVPN] Rotation triggered — reason: \(reason.rawValue)", category: .network, level: .info)

        if verifyIPChange {
            await captureCurrentIP()
        }

        if combinedShortcutEnabled {
            await executeCombinedShortcut(reason: reason)
        } else if shortcutDisconnectReconnectEnabled {
            await executeShortcutDisconnectReconnect(reason: reason)
        } else if autoRotationEnabled {
            await executeAutoRotation(reason: reason)
        } else if manualNotificationEnabled {
            await sendManualNotification(reason: reason)
        } else {
            logger.log("[NordVPN] No rotation strategy enabled", category: .network, level: .warning)
        }

        if verifyIPChange && verificationState != .failed && verificationState != .timedOut {
            await verifyIPChanged()
        }

        rotationCount += 1
        lastRotationDate = Date()
        lastRotationTime = Date()
        verificationState = .idle
        isRotating = false
        save()
    }

    // MARK: - Combined Shortcut (Single App Switch)

    private func executeCombinedShortcut(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Executing combined rotation shortcut", category: .network, level: .info)
        verificationState = .waitingForReconnect

        let url = shortcutURL(name: combinedShortcutName, withCallback: useCallbackURL)
        let success = await openShortcut(url: url)

        if success {
            let confirmed = await waitForRotationCompletion()
            if confirmed {
                logger.log("[NordVPN] Combined rotation confirmed", category: .network, level: .info)
                haptics.runStart()
            } else {
                logger.log("[NordVPN] Combined rotation — no confirmation within timeout, proceeding", category: .network, level: .warning)
            }
        } else {
            lastError = "Failed to trigger combined shortcut"
            verificationState = .failed
            logger.log("[NordVPN] Combined shortcut failed — falling back to notification", category: .network, level: .error)
            await sendManualNotification(reason: reason)
        }
    }

    // MARK: - Disconnect / Reconnect (Two App Switches)

    private func executeShortcutDisconnectReconnect(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Executing disconnect/reconnect via Shortcuts", category: .network, level: .info)
        verificationState = .waitingForDisconnect

        let disconnectURL = shortcutURL(name: disconnectShortcutName, withCallback: false)
        let disconnectSuccess = await openShortcut(url: disconnectURL)

        if disconnectSuccess {
            logger.log("[NordVPN] Disconnect shortcut triggered — waiting for network drop", category: .network, level: .info)
            await waitForNetworkDrop(timeout: adaptiveTimeoutSeconds)

            verificationState = .waitingForReconnect
            let reconnectURL = shortcutURL(name: reconnectShortcutName, withCallback: useCallbackURL)
            let reconnectSuccess = await openShortcut(url: reconnectURL)

            if reconnectSuccess {
                let confirmed = await waitForRotationCompletion()
                if confirmed {
                    logger.log("[NordVPN] Reconnect confirmed via adaptive polling", category: .network, level: .info)
                    haptics.runStart()
                } else {
                    logger.log("[NordVPN] Reconnect — no network confirmation within timeout, proceeding", category: .network, level: .warning)
                }
            } else {
                lastError = "Failed to trigger reconnect shortcut"
                verificationState = .failed
                logger.log("[NordVPN] Reconnect shortcut failed — falling back to notification", category: .network, level: .error)
                await sendManualNotification(reason: reason)
            }
        } else {
            lastError = "Failed to trigger disconnect shortcut"
            verificationState = .failed
            logger.log("[NordVPN] Disconnect shortcut failed — falling back to notification", category: .network, level: .error)
            await sendManualNotification(reason: reason)
        }
    }

    // MARK: - Auto Rotation

    private func executeAutoRotation(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Executing auto-rotation via Shortcuts", category: .network, level: .info)
        verificationState = .waitingForReconnect

        let rotateURL = shortcutURL(name: rotateShortcutName, withCallback: useCallbackURL)
        let success = await openShortcut(url: rotateURL)

        if success {
            let confirmed = await waitForRotationCompletion()
            if confirmed {
                logger.log("[NordVPN] Auto-rotation confirmed", category: .network, level: .info)
                haptics.runStart()
            } else {
                logger.log("[NordVPN] Auto-rotation — no confirmation within timeout", category: .network, level: .warning)
            }
        } else {
            lastError = "Failed to trigger rotation shortcut"
            verificationState = .failed
            logger.log("[NordVPN] Rotation shortcut failed — falling back to notification", category: .network, level: .error)
            await sendManualNotification(reason: reason)
        }
    }

    // MARK: - Adaptive Wait + Network Polling

    private func waitForRotationCompletion() async -> Bool {
        if useCallbackURL {
            let callbackResult = await waitForCallback(timeout: adaptiveTimeoutSeconds)
            if callbackResult { return true }
        }

        return await waitForNetworkRestore(timeout: adaptiveTimeoutSeconds)
    }

    private func waitForCallback(timeout: Double) async -> Bool {
        shortcutCallbackReceived = false

        return await withCheckedContinuation { continuation in
            self.callbackContinuation = continuation

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if !self.shortcutCallbackReceived {
                    self.callbackContinuation?.resume(returning: false)
                    self.callbackContinuation = nil
                }
            }
        }
    }

    private func waitForNetworkDrop(timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval: Duration = .milliseconds(300)

        while Date() < deadline {
            if !networkPathSatisfied {
                logger.log("[NordVPN] Network drop detected", category: .network, level: .info)
                return
            }
            try? await Task.sleep(for: pollInterval)
        }

        logger.log("[NordVPN] No network drop detected within \(String(format: "%.0f", timeout))s — proceeding", category: .network, level: .warning)
    }

    private func waitForNetworkRestore(timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval: Duration = .milliseconds(500)

        while Date() < deadline {
            if networkPathSatisfied {
                try? await Task.sleep(for: .seconds(1))
                if networkPathSatisfied {
                    logger.log("[NordVPN] Network restored and stable", category: .network, level: .info)
                    return true
                }
            }
            try? await Task.sleep(for: pollInterval)
        }

        verificationState = .timedOut
        logger.log("[NordVPN] Network restore timed out after \(String(format: "%.0f", timeout))s", category: .network, level: .warning)
        return false
    }

    // MARK: - IP Verification

    private func captureCurrentIP() async {
        guard let url = URL(string: ipCheckURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !ip.isEmpty {
                lastKnownIP = ip
                logger.log("[NordVPN] Current IP captured: \(ip)", category: .network, level: .info)
            }
        } catch {
            logger.log("[NordVPN] Failed to capture IP: \(error.localizedDescription)", category: .network, level: .warning)
        }
    }

    private func verifyIPChanged() async {
        guard let previousIP = lastKnownIP else { return }
        verificationState = .verifyingIPChange

        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            guard let url = URL(string: ipCheckURL) else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let newIP = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !newIP.isEmpty && newIP != previousIP {
                    lastVerifiedIP = newIP
                    ipChanged = true
                    verificationState = .confirmed
                    logger.log("[NordVPN] IP CHANGED: \(previousIP) → \(newIP)", category: .network, level: .info)
                    return
                }

                if attempt < maxAttempts {
                    try? await Task.sleep(for: .seconds(2))
                }
            } catch {
                logger.log("[NordVPN] IP check attempt \(attempt) failed: \(error.localizedDescription)", category: .network, level: .warning)
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        ipChanged = false
        lastVerifiedIP = previousIP
        verificationState = .confirmed
        logger.log("[NordVPN] IP did not change after rotation (same: \(previousIP)) — VPN may have reconnected to same server", category: .network, level: .warning)
    }

    // MARK: - Manual Notification

    func sendManualNotification(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Sending manual rotation notification", category: .network, level: .info)

        let content = UNMutableNotificationContent()
        content.title = "Rotate NordVPN Server"
        content.body = reason.notificationBody
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "nordvpn-rotate-\(UUID().uuidString.prefix(8))",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.log("[NordVPN] Notification delivered", category: .network, level: .info)
            haptics.autoPauseWarning()
        } catch {
            lastError = "Notification failed: \(error.localizedDescription)"
            logger.log("[NordVPN] Notification failed: \(error.localizedDescription)", category: .network, level: .error)
        }
    }

    // MARK: - Test & Diagnostics

    func testShortcut(name: String) async -> Bool {
        let url = shortcutURL(name: name, withCallback: false)
        return await openShortcut(url: url)
    }

    func fetchCurrentIP() async -> String? {
        guard let url = URL(string: ipCheckURL) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ip, !ip.isEmpty {
                lastVerifiedIP = ip
            }
            return ip
        } catch {
            return nil
        }
    }

    func shouldTriggerRotation(
        permDisabledCount: Int,
        failureRate: Double,
        consecutiveErrors: Int
    ) -> NordVPNTriggerReason? {
        if permDisabledCount > 0 {
            return .permDisabledDetected
        }
        if failureRate > 0.6 && consecutiveErrors >= 2 {
            return .fingerprintingDetected
        }
        if failureRate > 0.8 {
            return .highFailureRate
        }
        return nil
    }

    // MARK: - Private Helpers

    private func shortcutURL(name: String, withCallback: Bool) -> URL {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if withCallback {
            let successCallback = "sitchomatic://vpn-rotated".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let errorCallback = "sitchomatic://vpn-error".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(encoded)&x-success=\(successCallback)&x-error=\(errorCallback)")!
        }
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")!
    }

    @discardableResult
    private func openShortcut(url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func requestNotificationPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    // MARK: - Persistence

    func save() {
        let dict: [String: Any] = [
            "disconnectShortcutName": disconnectShortcutName,
            "reconnectShortcutName": reconnectShortcutName,
            "rotateShortcutName": rotateShortcutName,
            "combinedShortcutName": combinedShortcutName,
            "shortcutDisconnectReconnectEnabled": shortcutDisconnectReconnectEnabled,
            "combinedShortcutEnabled": combinedShortcutEnabled,
            "autoRotationEnabled": autoRotationEnabled,
            "manualNotificationEnabled": manualNotificationEnabled,
            "cooldownSeconds": cooldownSeconds,
            "rotationCount": rotationCount,
            "verifyIPChange": verifyIPChange,
            "adaptiveTimeoutSeconds": adaptiveTimeoutSeconds,
            "useCallbackURL": useCallbackURL
        ]
        UserDefaults.standard.set(dict, forKey: persistenceKey)
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: persistenceKey) else { return }
        if let val = dict["disconnectShortcutName"] as? String { disconnectShortcutName = val }
        if let val = dict["reconnectShortcutName"] as? String { reconnectShortcutName = val }
        if let val = dict["rotateShortcutName"] as? String { rotateShortcutName = val }
        if let val = dict["combinedShortcutName"] as? String { combinedShortcutName = val }
        if let val = dict["shortcutDisconnectReconnectEnabled"] as? Bool { shortcutDisconnectReconnectEnabled = val }
        if let val = dict["combinedShortcutEnabled"] as? Bool { combinedShortcutEnabled = val }
        if let val = dict["autoRotationEnabled"] as? Bool { autoRotationEnabled = val }
        if let val = dict["manualNotificationEnabled"] as? Bool { manualNotificationEnabled = val }
        if let val = dict["cooldownSeconds"] as? Double { cooldownSeconds = val }
        if let val = dict["rotationCount"] as? Int { rotationCount = val }
        if let val = dict["verifyIPChange"] as? Bool { verifyIPChange = val }
        if let val = dict["adaptiveTimeoutSeconds"] as? Double { adaptiveTimeoutSeconds = val }
        if let val = dict["useCallbackURL"] as? Bool { useCallbackURL = val }
    }

    func resetToDefaults() {
        disconnectShortcutName = "NordVPN Disconnect"
        reconnectShortcutName = "NordVPN Quick Connect"
        rotateShortcutName = "NordVPN Rotate Server"
        combinedShortcutName = "NordVPN Rotate"
        shortcutDisconnectReconnectEnabled = true
        combinedShortcutEnabled = false
        autoRotationEnabled = false
        manualNotificationEnabled = true
        cooldownSeconds = 10.0
        rotationCount = 0
        lastRotationDate = nil
        lastError = nil
        verifyIPChange = true
        adaptiveTimeoutSeconds = 15.0
        useCallbackURL = true
        lastKnownIP = nil
        lastVerifiedIP = nil
        ipChanged = false
        verificationState = .idle
        save()
    }
}

// MARK: - URL Query Helper

private extension URL {
    func queryValue(for key: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == key })?
            .value
    }
}
