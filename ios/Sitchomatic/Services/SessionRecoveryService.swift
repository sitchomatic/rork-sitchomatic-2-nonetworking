import Foundation

nonisolated struct EngineCheckpoint: Codable, Sendable {
    let waveIndex: Int
    let credentialIndex: Int
    let phase: String
    let completedCredentialIDs: [String]
    let failedCredentialIDs: [String]
    let pendingCredentialIDs: [String]
    let timestamp: Date
    let engineState: String
    let succeededCount: Int
    let failedCount: Int

    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 3600
    }
}

@MainActor
final class SessionRecoveryService {
    static let shared = SessionRecoveryService()

    private(set) var lastRecoveryTimestamp: Date?
    private(set) var recoveryCount: Int = 0
    private(set) var successfulRecoveries: Int = 0
    private(set) var failedRecoveries: Int = 0
    private let logger = DebugLogger.shared
    private let checkpointKey = "sitchomatic.v16.checkpoint"

    private init() {
        purgeStaleCheckpoints()
    }

    var recoverySuccessRate: Double {
        let total = successfulRecoveries + failedRecoveries
        guard total > 0 else { return 1.0 }
        return Double(successfulRecoveries) / Double(total)
    }

    func saveCheckpoint(credentialIndex: Int, waveIndex: Int, phase: String) {
        saveFullCheckpoint(EngineCheckpoint(
            waveIndex: waveIndex,
            credentialIndex: credentialIndex,
            phase: phase,
            completedCredentialIDs: [],
            failedCredentialIDs: [],
            pendingCredentialIDs: [],
            timestamp: Date(),
            engineState: phase,
            succeededCount: 0,
            failedCount: 0
        ))
    }

    func saveFullCheckpoint(_ checkpoint: EngineCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        UserDefaults.standard.set(data, forKey: checkpointKey)
    }

    func loadCheckpoint() -> (credentialIndex: Int, waveIndex: Int, phase: String)? {
        guard let checkpoint = loadFullCheckpoint() else { return nil }
        return (checkpoint.credentialIndex, checkpoint.waveIndex, checkpoint.phase)
    }

    func loadFullCheckpoint() -> EngineCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: checkpointKey),
              let checkpoint = try? JSONDecoder().decode(EngineCheckpoint.self, from: data) else { return nil }
        if checkpoint.isStale {
            clearCheckpoint()
            logger.log("Stale checkpoint purged (age > 1h)", category: .crash, level: .info)
            return nil
        }
        return checkpoint
    }

    func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: checkpointKey)
    }

    func recordRecovery() {
        recoveryCount += 1
        lastRecoveryTimestamp = Date()
        logger.log("Session recovery #\(recoveryCount)", category: .crash, level: .warning)
    }

    func recordRecoverySuccess() {
        successfulRecoveries += 1
        logger.log("Recovery succeeded (rate: \(String(format: "%.0f", recoverySuccessRate * 100))%)", category: .crash, level: .info)
    }

    func recordRecoveryFailure() {
        failedRecoveries += 1
        logger.log("Recovery failed (rate: \(String(format: "%.0f", recoverySuccessRate * 100))%)", category: .crash, level: .warning)
    }

    func hasResumableCheckpoint() -> Bool {
        loadFullCheckpoint() != nil
    }

    private func purgeStaleCheckpoints() {
        if let data = UserDefaults.standard.data(forKey: checkpointKey),
           let checkpoint = try? JSONDecoder().decode(EngineCheckpoint.self, from: data),
           checkpoint.isStale {
            clearCheckpoint()
        }
    }

    var diagnosticSummary: String {
        let hasCheckpoint = hasResumableCheckpoint()
        return "Recoveries: \(recoveryCount) (ok: \(successfulRecoveries), fail: \(failedRecoveries)) | Rate: \(String(format: "%.0f", recoverySuccessRate * 100))% | Checkpoint: \(hasCheckpoint ? "YES" : "none")"
    }
}
