import Foundation
import UIKit
import UserNotifications

nonisolated enum NordVPNRotationStrategy: String, Sendable, CaseIterable, Codable {
    case shortcutDisconnectReconnect
    case autoRotation
    case manualNotification

    var displayName: String {
        switch self {
        case .shortcutDisconnectReconnect: "Shortcut Disconnect/Reconnect"
        case .autoRotation: "Auto Rotation (Shortcut)"
        case .manualNotification: "Manual Notification"
        }
    }

    var description: String {
        switch self {
        case .shortcutDisconnectReconnect: "Triggers NordVPN disconnect then reconnect via Apple Shortcuts"
        case .autoRotation: "Automatically rotates NordVPN server via Shortcuts post-wave"
        case .manualNotification: "Sends a notification prompting you to manually rotate NordVPN"
        }
    }

    var iconName: String {
        switch self {
        case .shortcutDisconnectReconnect: "arrow.triangle.2.circlepath"
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

@Observable
@MainActor
final class NordVPNRotationService {
    static let shared = NordVPNRotationService()

    private(set) var lastRotationDate: Date?
    private(set) var rotationCount: Int = 0
    private(set) var lastTriggerReason: NordVPNTriggerReason?
    private(set) var isRotating: Bool = false
    private(set) var lastError: String?

    var disconnectShortcutName: String = "NordVPN Disconnect"
    var reconnectShortcutName: String = "NordVPN Quick Connect"
    var rotateShortcutName: String = "NordVPN Rotate Server"

    var shortcutDisconnectReconnectEnabled: Bool = true
    var autoRotationEnabled: Bool = false
    var manualNotificationEnabled: Bool = true

    var cooldownSeconds: Double = 10.0

    private let logger = DebugLogger.shared
    private let haptics = HapticService.shared
    private var lastRotationTime: Date = .distantPast

    private let persistenceKey = "sitchomatic.nordvpn.settings"

    private init() {
        load()
        requestNotificationPermission()
    }

    var isOnCooldown: Bool {
        Date().timeIntervalSince(lastRotationTime) < cooldownSeconds
    }

    var cooldownRemaining: TimeInterval {
        max(0, cooldownSeconds - Date().timeIntervalSince(lastRotationTime))
    }

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

        logger.log("[NordVPN] Rotation triggered — reason: \(reason.rawValue)", category: .network, level: .info)

        if shortcutDisconnectReconnectEnabled {
            await executeShortcutDisconnectReconnect(reason: reason)
        } else if autoRotationEnabled {
            await executeAutoRotation(reason: reason)
        } else if manualNotificationEnabled {
            await sendManualNotification(reason: reason)
        } else {
            logger.log("[NordVPN] No rotation strategy enabled", category: .network, level: .warning)
        }

        rotationCount += 1
        lastRotationDate = Date()
        lastRotationTime = Date()
        isRotating = false
        save()
    }

    func executeShortcutDisconnectReconnect(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Executing disconnect/reconnect via Shortcuts", category: .network, level: .info)

        let disconnectURL = shortcutURL(name: disconnectShortcutName)
        let success = await openShortcut(url: disconnectURL)

        if success {
            logger.log("[NordVPN] Disconnect shortcut triggered — waiting before reconnect", category: .network, level: .info)
            try? await Task.sleep(for: .seconds(3))

            let reconnectURL = shortcutURL(name: reconnectShortcutName)
            let reconnectSuccess = await openShortcut(url: reconnectURL)

            if reconnectSuccess {
                logger.log("[NordVPN] Reconnect shortcut triggered successfully", category: .network, level: .info)
                haptics.runStart()
            } else {
                lastError = "Failed to trigger reconnect shortcut"
                logger.log("[NordVPN] Reconnect shortcut failed — falling back to notification", category: .network, level: .error)
                await sendManualNotification(reason: reason)
            }
        } else {
            lastError = "Failed to trigger disconnect shortcut"
            logger.log("[NordVPN] Disconnect shortcut failed — falling back to notification", category: .network, level: .error)
            await sendManualNotification(reason: reason)
        }
    }

    func executeAutoRotation(reason: NordVPNTriggerReason) async {
        logger.log("[NordVPN] Executing auto-rotation via Shortcuts", category: .network, level: .info)

        let rotateURL = shortcutURL(name: rotateShortcutName)
        let success = await openShortcut(url: rotateURL)

        if success {
            logger.log("[NordVPN] Rotation shortcut triggered — waiting for server change", category: .network, level: .info)
            try? await Task.sleep(for: .seconds(5))
            haptics.runStart()
        } else {
            lastError = "Failed to trigger rotation shortcut"
            logger.log("[NordVPN] Rotation shortcut failed — falling back to notification", category: .network, level: .error)
            await sendManualNotification(reason: reason)
        }
    }

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

    func testShortcut(name: String) async -> Bool {
        let url = shortcutURL(name: name)
        return await openShortcut(url: url)
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

    var activeStrategyName: String {
        if shortcutDisconnectReconnectEnabled { return NordVPNRotationStrategy.shortcutDisconnectReconnect.displayName }
        if autoRotationEnabled { return NordVPNRotationStrategy.autoRotation.displayName }
        if manualNotificationEnabled { return NordVPNRotationStrategy.manualNotification.displayName }
        return "None"
    }

    var diagnosticSummary: String {
        let lastRotation = lastRotationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "Never"
        return "Strategy: \(activeStrategyName) | Rotations: \(rotationCount) | Last: \(lastRotation) | Cooldown: \(isOnCooldown ? String(format: "%.0fs", cooldownRemaining) : "Ready")"
    }

    // MARK: - Private

    private func shortcutURL(name: String) -> URL {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
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

    func save() {
        let dict: [String: Any] = [
            "disconnectShortcutName": disconnectShortcutName,
            "reconnectShortcutName": reconnectShortcutName,
            "rotateShortcutName": rotateShortcutName,
            "shortcutDisconnectReconnectEnabled": shortcutDisconnectReconnectEnabled,
            "autoRotationEnabled": autoRotationEnabled,
            "manualNotificationEnabled": manualNotificationEnabled,
            "cooldownSeconds": cooldownSeconds,
            "rotationCount": rotationCount
        ]
        UserDefaults.standard.set(dict, forKey: persistenceKey)
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: persistenceKey) else { return }
        if let val = dict["disconnectShortcutName"] as? String { disconnectShortcutName = val }
        if let val = dict["reconnectShortcutName"] as? String { reconnectShortcutName = val }
        if let val = dict["rotateShortcutName"] as? String { rotateShortcutName = val }
        if let val = dict["shortcutDisconnectReconnectEnabled"] as? Bool { shortcutDisconnectReconnectEnabled = val }
        if let val = dict["autoRotationEnabled"] as? Bool { autoRotationEnabled = val }
        if let val = dict["manualNotificationEnabled"] as? Bool { manualNotificationEnabled = val }
        if let val = dict["cooldownSeconds"] as? Double { cooldownSeconds = val }
        if let val = dict["rotationCount"] as? Int { rotationCount = val }
    }

    func resetToDefaults() {
        disconnectShortcutName = "NordVPN Disconnect"
        reconnectShortcutName = "NordVPN Quick Connect"
        rotateShortcutName = "NordVPN Rotate Server"
        shortcutDisconnectReconnectEnabled = true
        autoRotationEnabled = false
        manualNotificationEnabled = true
        cooldownSeconds = 10.0
        rotationCount = 0
        lastRotationDate = nil
        lastError = nil
        save()
    }
}
