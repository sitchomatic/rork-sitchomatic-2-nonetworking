import Foundation

nonisolated enum MemoryPressureLevel: String, Sendable {
    case safe
    case elevated
    case critical
    case emergency

    var suggestedMaxConcurrency: Int {
        switch self {
        case .safe: 12
        case .elevated: 6
        case .critical: 3
        case .emergency: 1
        }
    }
}

@MainActor
final class CrashProtectionService {
    static let shared = CrashProtectionService()

    private(set) var isMonitoring: Bool = false
    private(set) var currentMemoryUsageMB: Double = 0
    private(set) var peakMemoryUsageMB: Double = 0
    private(set) var crashCount: Int = 0
    private(set) var lastCrashDate: Date?
    private(set) var cooldownUntil: Date?
    private var monitorTask: Task<Void, Never>?

    private var baseMemoryCriticalThresholdMB: Double {
        Double(AutomationSettings.shared.memoryCriticalThresholdMB)
    }
    private var baseMemoryEmergencyThresholdMB: Double {
        Double(AutomationSettings.shared.memoryEmergencyThresholdMB)
    }
    private var baseMemorySafeThresholdMB: Double {
        Double(AutomationSettings.shared.memorySafeThresholdMB)
    }
    private var baseMemoryElevatedThresholdMB: Double {
        Double(AutomationSettings.shared.memoryElevatedThresholdMB)
    }

    private let thresholdReductionPerCrash: Double = 30
    private let maxThresholdReduction: Double = 200
    private let cooldownBaseDurationSeconds: TimeInterval = 5
    private let cooldownMaxDurationSeconds: TimeInterval = 60

    private let logger = DebugLogger.shared

    private init() {}

    private var thresholdReduction: Double {
        min(Double(crashCount) * thresholdReductionPerCrash, maxThresholdReduction)
    }

    private var memoryCriticalThresholdMB: Double { baseMemoryCriticalThresholdMB - thresholdReduction }
    private var memoryEmergencyThresholdMB: Double { baseMemoryEmergencyThresholdMB - thresholdReduction }
    private var memorySafeThresholdMB: Double { baseMemorySafeThresholdMB - thresholdReduction }
    private var memoryElevatedThresholdMB: Double { baseMemoryElevatedThresholdMB - thresholdReduction }

    var memoryPressureLevel: MemoryPressureLevel {
        if currentMemoryUsageMB > memoryEmergencyThresholdMB { return .emergency }
        if currentMemoryUsageMB > memoryCriticalThresholdMB { return .critical }
        if currentMemoryUsageMB > memoryElevatedThresholdMB { return .elevated }
        return .safe
    }

    var isMemoryCritical: Bool { memoryPressureLevel == .critical || memoryPressureLevel == .emergency }
    var isMemoryEmergency: Bool { memoryPressureLevel == .emergency }
    var isMemorySafeForNewSession: Bool { memoryPressureLevel == .safe && !isInCooldown }
    var shouldReduceConcurrency: Bool { memoryPressureLevel != .safe }

    var isInCooldown: Bool {
        guard let cooldownUntil else { return false }
        return Date() < cooldownUntil
    }

    var cooldownRemainingSeconds: TimeInterval {
        guard let cooldownUntil else { return 0 }
        return max(0, cooldownUntil.timeIntervalSinceNow)
    }

    var suggestedConcurrency: Int {
        if isInCooldown { return 1 }
        return memoryPressureLevel.suggestedMaxConcurrency
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateMemoryUsage()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }

    func waitForMemoryToDrop(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            updateMemoryUsage()
            if memoryPressureLevel == .safe { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return memoryPressureLevel == .safe
    }

    func waitForCooldown() async {
        while isInCooldown {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func recordCrash() {
        crashCount += 1
        lastCrashDate = Date()

        let cooldownDuration = min(
            cooldownBaseDurationSeconds * pow(1.5, Double(min(crashCount, 10))),
            cooldownMaxDurationSeconds
        )
        cooldownUntil = Date().addingTimeInterval(cooldownDuration)

        logger.log(
            "Crash #\(crashCount) recorded — cooldown \(String(format: "%.1f", cooldownDuration))s, thresholds reduced by \(String(format: "%.0f", thresholdReduction))MB",
            category: .crash,
            level: .error
        )
    }

    func resetCrashHistory() {
        crashCount = 0
        lastCrashDate = nil
        cooldownUntil = nil
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            currentMemoryUsageMB = Double(info.resident_size) / 1_048_576
            peakMemoryUsageMB = max(peakMemoryUsageMB, currentMemoryUsageMB)
        }
    }

    var diagnosticSummary: String {
        let level = memoryPressureLevel.rawValue.uppercased()
        let cooldown = isInCooldown ? " | Cooldown: \(String(format: "%.0f", cooldownRemainingSeconds))s" : ""
        return "Memory: \(String(format: "%.0f", currentMemoryUsageMB))MB (peak: \(String(format: "%.0f", peakMemoryUsageMB))MB) | Level: \(level) | Crashes: \(crashCount) | Suggested conc: \(suggestedConcurrency)\(cooldown)"
    }
}
