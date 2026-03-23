import Foundation

nonisolated struct LoginCredential: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    var username: String
    var password: String
    var passwords: [String]
    var displayName: String
    var isEnabled: Bool
    var lastAttemptDate: Date?
    var lastOutcome: String?
    var totalAttempts: Int
    var successCount: Int
    var failCount: Int
    var tags: [String]
    var lastTestedPasswordIndex: Int
    var passwordPhaseOutcomes: [String]

    var passwordCount: Int { passwords.count }
    var hasMultiplePasswords: Bool { passwords.count > 1 }

    func passwordAt(phase: Int) -> String? {
        guard phase >= 0, phase < passwords.count else { return nil }
        return passwords[phase]
    }

    func credentialForPhase(_ phase: Int) -> LoginCredential {
        var copy = self
        if let pw = passwordAt(phase: phase) {
            copy.password = pw
        }
        return copy
    }

    var allPasswordsExhausted: Bool {
        lastTestedPasswordIndex >= passwords.count - 1
    }

    var nextPasswordPhase: Int? {
        let next = lastTestedPasswordIndex + 1
        guard next < passwords.count else { return nil }
        return next
    }

    init(
        id: UUID = UUID(),
        username: String,
        password: String,
        passwords: [String]? = nil,
        displayName: String = "",
        isEnabled: Bool = true,
        lastAttemptDate: Date? = nil,
        lastOutcome: String? = nil,
        totalAttempts: Int = 0,
        successCount: Int = 0,
        failCount: Int = 0,
        tags: [String] = [],
        lastTestedPasswordIndex: Int = -1,
        passwordPhaseOutcomes: [String] = []
    ) {
        self.id = id
        self.username = username
        self.password = password
        self.passwords = passwords ?? [password]
        self.displayName = displayName.isEmpty ? username : displayName
        self.isEnabled = isEnabled
        self.lastAttemptDate = lastAttemptDate
        self.lastOutcome = lastOutcome
        self.totalAttempts = totalAttempts
        self.successCount = successCount
        self.failCount = failCount
        self.tags = tags
        self.lastTestedPasswordIndex = lastTestedPasswordIndex
        self.passwordPhaseOutcomes = passwordPhaseOutcomes
    }

    mutating func addPassword(_ pw: String) {
        guard !passwords.contains(pw) else { return }
        passwords.append(pw)
    }

    mutating func recordPhaseOutcome(_ outcome: String, phase: Int) {
        lastTestedPasswordIndex = phase
        while passwordPhaseOutcomes.count <= phase {
            passwordPhaseOutcomes.append("")
        }
        passwordPhaseOutcomes[phase] = outcome
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
        case "incorrectPassword": return "key.slash"
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
        case "incorrectPassword": return "gray"
        default: return "secondary"
        }
    }

    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempts)
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, username, password, passwords, displayName, isEnabled
        case lastAttemptDate, lastOutcome, totalAttempts, successCount, failCount
        case tags, lastTestedPasswordIndex, passwordPhaseOutcomes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        passwords = (try? container.decode([String].self, forKey: .passwords)) ?? [password]
        displayName = try container.decode(String.self, forKey: .displayName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        lastAttemptDate = try container.decodeIfPresent(Date.self, forKey: .lastAttemptDate)
        lastOutcome = try container.decodeIfPresent(String.self, forKey: .lastOutcome)
        totalAttempts = try container.decode(Int.self, forKey: .totalAttempts)
        successCount = try container.decode(Int.self, forKey: .successCount)
        failCount = try container.decode(Int.self, forKey: .failCount)
        tags = try container.decode([String].self, forKey: .tags)
        lastTestedPasswordIndex = (try? container.decode(Int.self, forKey: .lastTestedPasswordIndex)) ?? -1
        passwordPhaseOutcomes = (try? container.decode([String].self, forKey: .passwordPhaseOutcomes)) ?? []
        if passwords.isEmpty {
            passwords = [password]
        }
    }
}
