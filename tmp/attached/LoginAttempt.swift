import Foundation

@Observable
final class LoginAttempt: Identifiable {
    let id: UUID
    let credential: LoginCredential
    let sessionIndex: Int
    var status: LoginAttemptStatus
    var startedAt: Date?
    var completedAt: Date?
    var logs: [LogEntry]
    var errorMessage: String?
    var responseSnippet: String?

    init(credential: LoginCredential, sessionIndex: Int) {
        self.id = UUID()
        self.credential = credential
        self.sessionIndex = sessionIndex
        self.status = .queued
        self.logs = []
    }

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        return (completedAt ?? Date()).timeIntervalSince(start)
    }

    var formattedDuration: String {
        guard let d = duration else { return "—" }
        return String(format: "%.1fs", d)
    }
}

nonisolated enum LoginAttemptStatus: String, Codable, Sendable {
    case queued = "Queued"
    case running = "Running"
    case success = "Success"
    case tempDisabled = "Temp Disabled"
    case permDisabled = "Perm Disabled"
    case noAccount = "No Account"
    case unsure = "Unsure"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .tempDisabled: return "clock.fill"
        case .permDisabled: return "xmark.octagon.fill"
        case .noAccount: return "person.slash.fill"
        case .unsure: return "questionmark.diamond.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .queued, .running: return false
        default: return true
        }
    }
}
