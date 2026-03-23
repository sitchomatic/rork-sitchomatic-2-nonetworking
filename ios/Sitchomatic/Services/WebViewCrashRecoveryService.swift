import Foundation

@MainActor
final class WebViewCrashRecoveryService {
    static let shared = WebViewCrashRecoveryService()

    private(set) var totalRecoveries: Int = 0
    private(set) var successfulRecoveries: Int = 0
    private(set) var failedRecoveries: Int = 0
    private(set) var lastRecoveryDate: Date?
    private let logger = DebugLogger.shared
    private let maxRecoveriesPerMinute: Int = 5
    private var recentRecoveries: [Date] = []
    private var crashCounts: [String: Int] = [:]
    private var blacklistedCredentials: Set<String> = []
    private let blacklistThreshold: Int = 3

    private init() {}

    var canRecover: Bool {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        recentRecoveries = recentRecoveries.filter { $0 > oneMinuteAgo }
        return recentRecoveries.count < maxRecoveriesPerMinute
    }

    var recoverySuccessRate: Double {
        let total = successfulRecoveries + failedRecoveries
        guard total > 0 else { return 1.0 }
        return Double(successfulRecoveries) / Double(total)
    }

    func isCredentialBlacklisted(_ credentialID: String) -> Bool {
        blacklistedCredentials.contains(credentialID)
    }

    func recordRecovery(pageID: String, phase: String) {
        totalRecoveries += 1
        lastRecoveryDate = Date()
        recentRecoveries.append(Date())

        crashCounts[pageID, default: 0] += 1
        if crashCounts[pageID, default: 0] >= blacklistThreshold {
            blacklistedCredentials.insert(pageID)
            logger.log("Credential \(pageID) blacklisted after \(blacklistThreshold) crashes", category: .crash, level: .error)
        }

        logger.log("WebView crash recovery #\(totalRecoveries) — page: \(pageID), phase: \(phase)", category: .crash, level: .warning)
    }

    func recordRecoverySuccess(pageID: String) {
        successfulRecoveries += 1
        crashCounts[pageID] = max(0, (crashCounts[pageID] ?? 1) - 1)
        if crashCounts[pageID] == 0 {
            blacklistedCredentials.remove(pageID)
        }
    }

    func recordRecoveryFailure(pageID: String) {
        failedRecoveries += 1
    }

    func backoffDuration(for credentialID: String) -> TimeInterval {
        let crashes = crashCounts[credentialID, default: 0]
        guard crashes > 0 else { return 0 }
        let base: TimeInterval = 1.0
        let backoff = base * pow(2.0, Double(min(crashes - 1, 6)))
        let jitter = Double.random(in: 0...0.5)
        return backoff + jitter
    }

    func clearBlacklist() {
        blacklistedCredentials.removeAll()
        crashCounts.removeAll()
    }

    func reset() {
        totalRecoveries = 0
        successfulRecoveries = 0
        failedRecoveries = 0
        lastRecoveryDate = nil
        recentRecoveries.removeAll()
        crashCounts.removeAll()
        blacklistedCredentials.removeAll()
    }

    var diagnosticSummary: String {
        "Recoveries: \(totalRecoveries) (ok: \(successfulRecoveries), fail: \(failedRecoveries)) | Rate: \(String(format: "%.0f", recoverySuccessRate * 100))% | Blacklisted: \(blacklistedCredentials.count)"
    }
}
