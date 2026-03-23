import Foundation

@MainActor
final class PersistenceService {
    static let shared = PersistenceService()

    private let credentialsKey = "sitchomatic.v16.credentials"
    private let attemptsKey = "sitchomatic.v16.attempts"
    private let settingsKey = "sitchomatic.v16.settings"
    private let logger = DebugLogger.shared

    private init() {}

    func saveCredentials(_ credentials: [LoginCredential]) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        UserDefaults.standard.set(data, forKey: credentialsKey)
    }

    func loadCredentials() -> [LoginCredential] {
        guard let data = UserDefaults.standard.data(forKey: credentialsKey),
              let decoded = try? JSONDecoder().decode([LoginCredential].self, from: data) else { return [] }
        return decoded
    }

    func saveAttempts(_ attempts: [LoginAttempt]) {
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        UserDefaults.standard.set(data, forKey: attemptsKey)
    }

    func loadAttempts() -> [LoginAttempt] {
        guard let data = UserDefaults.standard.data(forKey: attemptsKey),
              let decoded = try? JSONDecoder().decode([LoginAttempt].self, from: data) else { return [] }
        return decoded
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: credentialsKey)
        UserDefaults.standard.removeObject(forKey: attemptsKey)
        UserDefaults.standard.removeObject(forKey: settingsKey)
        logger.log("All persisted data cleared", category: .persistence, level: .warning)
    }
}
