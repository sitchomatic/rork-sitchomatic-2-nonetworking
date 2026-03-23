import Foundation

nonisolated struct LoginCredential: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    var username: String
    var password: String
    var displayName: String
    var isEnabled: Bool
    var lastAttemptDate: Date?
    var lastOutcome: String?
    var totalAttempts: Int
    var successCount: Int
    var failCount: Int
    var tags: [String]

    init(
        id: UUID = UUID(),
        username: String,
        password: String,
        displayName: String = "",
        isEnabled: Bool = true,
        lastAttemptDate: Date? = nil,
        lastOutcome: String? = nil,
        totalAttempts: Int = 0,
        successCount: Int = 0,
        failCount: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.username = username
        self.password = password
        self.displayName = displayName.isEmpty ? username : displayName
        self.isEnabled = isEnabled
        self.lastAttemptDate = lastAttemptDate
        self.lastOutcome = lastOutcome
        self.totalAttempts = totalAttempts
        self.successCount = successCount
        self.failCount = failCount
        self.tags = tags
    }

    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempts)
    }

    var statusIcon: String {
        guard let outcome = lastOutcome else { return "circle" }
        switch outcome {
        case "success": return "checkmark.seal.fill"
        case "noAccount": return "person.slash.fill"
        case "permDisabled": return "lock.slash.fill"
        case "tempDisabled": return "clock.badge.exclamationmark.fill"
        case "unsure": return "questionmark.diamond.fill"
        case "error": return "exclamationmark.octagon.fill"
        default: return "questionmark.circle"
        }
    }

    var statusColor: String {
        guard let outcome = lastOutcome else { return "secondary" }
        switch outcome {
        case "success": return "green"
        case "noAccount": return "indigo"
        case "permDisabled": return "red"
        case "tempDisabled": return "orange"
        case "unsure": return "purple"
        case "error": return "yellow"
        default: return "secondary"
        }
    }
}
