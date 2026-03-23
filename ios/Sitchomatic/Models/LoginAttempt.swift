import Foundation

nonisolated struct LoginAttempt: Identifiable, Sendable, Codable {
    let id: UUID
    let credentialID: UUID
    let timestamp: Date
    let outcome: String
    let joeOutcome: String
    let ignitionOutcome: String
    let duration: TimeInterval
    let proxyUsed: String
    let errorMessage: String?
    let speedMode: String

    init(
        id: UUID = UUID(),
        credentialID: UUID,
        timestamp: Date = Date(),
        outcome: String,
        joeOutcome: String,
        ignitionOutcome: String,
        duration: TimeInterval,
        proxyUsed: String,
        errorMessage: String? = nil,
        speedMode: String = "balanced"
    ) {
        self.id = id
        self.credentialID = credentialID
        self.timestamp = timestamp
        self.outcome = outcome
        self.joeOutcome = joeOutcome
        self.ignitionOutcome = ignitionOutcome
        self.duration = duration
        self.proxyUsed = proxyUsed
        self.errorMessage = errorMessage
        self.speedMode = speedMode
    }
}
