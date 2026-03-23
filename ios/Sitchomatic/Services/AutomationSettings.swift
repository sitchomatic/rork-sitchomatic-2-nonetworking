import Foundation

@Observable
@MainActor
final class AutomationSettings {
    static let shared = AutomationSettings()

    var speedMode: SpeedMode = .balanced
    var maxConcurrentPairs: Int = 6
    var autoRetryOnFailure: Bool = true
    var maxRetryAttempts: Int = 3
    var captureScreenshotsOnFailure: Bool = true
    var enableTracing: Bool = true
    var interWaveDelaySeconds: Double = 2.0
    var joeURL: String = AutomationSite.joe.defaultLoginURL
    var ignitionURL: String = AutomationSite.ignition.defaultLoginURL
    var availableSites: [AutomationSite] { AutomationSite.allCases }
    var stealthEnabled: Bool = true
    var fingerprintRotation: Bool = true

    var navigationTimeoutOverride: Double = 0
    var selectorTimeoutOverride: Double = 0
    var webViewHardCap: Int = 24
    var staleSessionTimeoutSeconds: Int = 300
    var preWarmCount: Int = 2
    var wipeDataOnRelease: Bool = true
    var userAgentRotation: Bool = true
    var logRetentionLimit: Int = 5000
    var minimumLogLevel: Int = 1

    var memoryCriticalThresholdMB: Int = 800
    var memoryEmergencyThresholdMB: Int = 1000
    var memorySafeThresholdMB: Int = 500
    var memoryElevatedThresholdMB: Int = 600
    var cooldownBaseDuration: Double = 5.0

    var connectionTimeoutSeconds: Double = 30.0
    var requestTimeoutSeconds: Double = 60.0
    var proxyRotationIntervalSeconds: Int = 0
    var dnsPreference: DNSPreference = .system
    var networkIsolationStrict: Bool = true
    var proxyHealthCheckOnConnect: Bool = true
    var autoReconnect: Bool = true
    var maxNetworkRetries: Int = 3
    var bandwidthMonitoring: Bool = false

    private let persistenceKey = "sitchomatic.v16.automationSettings"

    private init() {
        load()
        applyDefaultURLsIfNeeded()
    }

    func save() {
        applyDefaultURLsIfNeeded()
        let dict: [String: Any] = [
            "speedMode": speedMode.rawValue,
            "maxConcurrentPairs": maxConcurrentPairs,
            "autoRetryOnFailure": autoRetryOnFailure,
            "maxRetryAttempts": maxRetryAttempts,
            "captureScreenshotsOnFailure": captureScreenshotsOnFailure,
            "enableTracing": enableTracing,
            "interWaveDelaySeconds": interWaveDelaySeconds,
            "joeURL": joeURL,
            "ignitionURL": ignitionURL,
            "stealthEnabled": stealthEnabled,
            "fingerprintRotation": fingerprintRotation,
            "navigationTimeoutOverride": navigationTimeoutOverride,
            "selectorTimeoutOverride": selectorTimeoutOverride,
            "webViewHardCap": webViewHardCap,
            "staleSessionTimeoutSeconds": staleSessionTimeoutSeconds,
            "preWarmCount": preWarmCount,
            "wipeDataOnRelease": wipeDataOnRelease,
            "userAgentRotation": userAgentRotation,
            "logRetentionLimit": logRetentionLimit,
            "minimumLogLevel": minimumLogLevel,
            "memoryCriticalThresholdMB": memoryCriticalThresholdMB,
            "memoryEmergencyThresholdMB": memoryEmergencyThresholdMB,
            "memorySafeThresholdMB": memorySafeThresholdMB,
            "memoryElevatedThresholdMB": memoryElevatedThresholdMB,
            "cooldownBaseDuration": cooldownBaseDuration,
            "connectionTimeoutSeconds": connectionTimeoutSeconds,
            "requestTimeoutSeconds": requestTimeoutSeconds,
            "proxyRotationIntervalSeconds": proxyRotationIntervalSeconds,
            "dnsPreference": dnsPreference.rawValue,
            "networkIsolationStrict": networkIsolationStrict,
            "proxyHealthCheckOnConnect": proxyHealthCheckOnConnect,
            "autoReconnect": autoReconnect,
            "maxNetworkRetries": maxNetworkRetries,
            "bandwidthMonitoring": bandwidthMonitoring
        ]
        UserDefaults.standard.set(dict, forKey: persistenceKey)
    }

    func loginURL(for site: AutomationSite) -> String {
        switch site {
        case .joe:
            normalizedURL(joeURL, fallback: .joe)
        case .ignition:
            normalizedURL(ignitionURL, fallback: .ignition)
        }
    }

    func setLoginURL(_ value: String, for site: AutomationSite) {
        switch site {
        case .joe:
            joeURL = normalizedURL(value, fallback: .joe)
        case .ignition:
            ignitionURL = normalizedURL(value, fallback: .ignition)
        }
    }

    func resetLoginURLsToDefaults() {
        joeURL = AutomationSite.joe.defaultLoginURL
        ignitionURL = AutomationSite.ignition.defaultLoginURL
        save()
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: persistenceKey) else { return }
        if let raw = dict["speedMode"] as? String, let mode = SpeedMode(rawValue: raw) { speedMode = mode }
        if let val = dict["maxConcurrentPairs"] as? Int { maxConcurrentPairs = val }
        if let val = dict["autoRetryOnFailure"] as? Bool { autoRetryOnFailure = val }
        if let val = dict["maxRetryAttempts"] as? Int { maxRetryAttempts = val }
        if let val = dict["captureScreenshotsOnFailure"] as? Bool { captureScreenshotsOnFailure = val }
        if let val = dict["enableTracing"] as? Bool { enableTracing = val }
        if let val = dict["interWaveDelaySeconds"] as? Double { interWaveDelaySeconds = val }
        if let val = dict["joeURL"] as? String { joeURL = val }
        if let val = dict["ignitionURL"] as? String { ignitionURL = val }
        if let val = dict["stealthEnabled"] as? Bool { stealthEnabled = val }
        if let val = dict["fingerprintRotation"] as? Bool { fingerprintRotation = val }
        if let val = dict["navigationTimeoutOverride"] as? Double { navigationTimeoutOverride = val }
        if let val = dict["selectorTimeoutOverride"] as? Double { selectorTimeoutOverride = val }
        if let val = dict["webViewHardCap"] as? Int { webViewHardCap = val }
        if let val = dict["staleSessionTimeoutSeconds"] as? Int { staleSessionTimeoutSeconds = val }
        if let val = dict["preWarmCount"] as? Int { preWarmCount = val }
        if let val = dict["wipeDataOnRelease"] as? Bool { wipeDataOnRelease = val }
        if let val = dict["userAgentRotation"] as? Bool { userAgentRotation = val }
        if let val = dict["logRetentionLimit"] as? Int { logRetentionLimit = val }
        if let val = dict["minimumLogLevel"] as? Int { minimumLogLevel = val }
        if let val = dict["memoryCriticalThresholdMB"] as? Int { memoryCriticalThresholdMB = val }
        if let val = dict["memoryEmergencyThresholdMB"] as? Int { memoryEmergencyThresholdMB = val }
        if let val = dict["memorySafeThresholdMB"] as? Int { memorySafeThresholdMB = val }
        if let val = dict["memoryElevatedThresholdMB"] as? Int { memoryElevatedThresholdMB = val }
        if let val = dict["cooldownBaseDuration"] as? Double { cooldownBaseDuration = val }
        if let val = dict["connectionTimeoutSeconds"] as? Double { connectionTimeoutSeconds = val }
        if let val = dict["requestTimeoutSeconds"] as? Double { requestTimeoutSeconds = val }
        if let val = dict["proxyRotationIntervalSeconds"] as? Int { proxyRotationIntervalSeconds = val }
        if let raw = dict["dnsPreference"] as? String, let dns = DNSPreference(rawValue: raw) { dnsPreference = dns }
        if let val = dict["networkIsolationStrict"] as? Bool { networkIsolationStrict = val }
        if let val = dict["proxyHealthCheckOnConnect"] as? Bool { proxyHealthCheckOnConnect = val }
        if let val = dict["autoReconnect"] as? Bool { autoReconnect = val }
        if let val = dict["maxNetworkRetries"] as? Int { maxNetworkRetries = val }
        if let val = dict["bandwidthMonitoring"] as? Bool { bandwidthMonitoring = val }
    }

    private func applyDefaultURLsIfNeeded() {
        joeURL = normalizedURL(joeURL, fallback: .joe)
        ignitionURL = normalizedURL(ignitionURL, fallback: .ignition)
    }

    var effectiveNavigationTimeout: TimeInterval {
        navigationTimeoutOverride > 0 ? navigationTimeoutOverride : speedMode.navigationTimeoutSeconds
    }

    var effectiveSelectorTimeout: TimeInterval {
        selectorTimeoutOverride > 0 ? selectorTimeoutOverride : speedMode.selectorTimeoutSeconds
    }

    func resetNetworkDefaults() {
        connectionTimeoutSeconds = 30.0
        requestTimeoutSeconds = 60.0
        proxyRotationIntervalSeconds = 0
        dnsPreference = .system
        networkIsolationStrict = true
        proxyHealthCheckOnConnect = true
        autoReconnect = true
        maxNetworkRetries = 3
        bandwidthMonitoring = false
        save()
    }

    func resetMemoryDefaults() {
        memoryCriticalThresholdMB = 800
        memoryEmergencyThresholdMB = 1000
        memorySafeThresholdMB = 500
        memoryElevatedThresholdMB = 600
        cooldownBaseDuration = 5.0
        save()
    }

    func resetWebViewDefaults() {
        webViewHardCap = 24
        staleSessionTimeoutSeconds = 300
        preWarmCount = 2
        wipeDataOnRelease = true
        userAgentRotation = true
        save()
    }

    private func normalizedURL(_ value: String, fallback site: AutomationSite) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? site.defaultLoginURL : trimmedValue
    }
}

nonisolated enum DNSPreference: String, Sendable, CaseIterable, Codable {
    case system
    case cloudflare
    case google
    case quad9

    var displayName: String {
        switch self {
        case .system: "System Default"
        case .cloudflare: "Cloudflare (1.1.1.1)"
        case .google: "Google (8.8.8.8)"
        case .quad9: "Quad9 (9.9.9.9)"
        }
    }

    var primaryAddress: String {
        switch self {
        case .system: ""
        case .cloudflare: "1.1.1.1"
        case .google: "8.8.8.8"
        case .quad9: "9.9.9.9"
        }
    }

    var secondaryAddress: String {
        switch self {
        case .system: ""
        case .cloudflare: "1.0.0.1"
        case .google: "8.8.4.4"
        case .quad9: "149.112.112.112"
        }
    }
}
