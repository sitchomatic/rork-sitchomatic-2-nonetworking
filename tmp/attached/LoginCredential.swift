import Foundation

@Observable
final class LoginCredential: Identifiable {
    let id: String
    var username: String
    var password: String
    var status: CredentialStatus
    var addedAt: Date
    var notes: String
    var testResults: [LoginTestResult]
    var lastTestedAt: Date?

    init(username: String, password: String, id: String? = nil, addedAt: Date? = nil) {
        self.id = id ?? UUID().uuidString
        self.username = username
        self.password = password
        self.status = .untested
        self.addedAt = addedAt ?? Date()
        self.notes = ""
        self.testResults = []
    }

    var exportFormat: String {
        "\(username):\(password)"
    }

    func recordResult(success: Bool, duration: TimeInterval, error: String? = nil, detail: String? = nil) {
        let result = LoginTestResult(success: success, duration: duration, errorMessage: error, responseDetail: detail)
        testResults.insert(result, at: 0)
        lastTestedAt = Date()

        if testResults.count > 50 {
            testResults = Array(testResults.prefix(50))
        }

        if success {
            status = .working
        } else if let d = detail?.lowercased() {
            if d.contains("perm disabled") || d.contains("permanently") || d.contains("blacklist") {
                status = .permDisabled
            } else if d.contains("temp disabled") || d.contains("temporarily") {
                status = .tempDisabled
            } else if d.contains("no account") || d.contains("incorrect") {
                status = .noAccount
            } else {
                status = .unsure
            }
        } else {
            status = .unsure
        }
    }

    static func smartParse(_ input: String) -> [LoginCredential] {
        input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { parseLine($0) }
    }

    static func parseLine(_ line: String) -> LoginCredential? {
        let separators = [":", "|", ";", ",", "\t"]
        for sep in separators {
            let parts = line.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2, parts[0].count >= 3, !parts[1].isEmpty {
                return LoginCredential(username: parts[0], password: parts[1])
            }
        }
        return nil
    }
}

nonisolated enum CredentialStatus: String, Codable, CaseIterable, Sendable {
    case untested = "Untested"
    case working = "Working"
    case tempDisabled = "Temp Disabled"
    case permDisabled = "Perm Disabled"
    case noAccount = "No Account"
    case unsure = "Unsure"
    case blacklisted = "Blacklisted"

    var icon: String {
        switch self {
        case .untested: return "questionmark.circle"
        case .working: return "checkmark.circle.fill"
        case .tempDisabled: return "clock.fill"
        case .permDisabled: return "xmark.octagon.fill"
        case .noAccount: return "person.slash.fill"
        case .unsure: return "exclamationmark.triangle.fill"
        case .blacklisted: return "nosign"
        }
    }

    var color: String {
        switch self {
        case .untested: return "secondary"
        case .working: return "green"
        case .tempDisabled: return "orange"
        case .permDisabled: return "red"
        case .noAccount: return "gray"
        case .unsure: return "yellow"
        case .blacklisted: return "red"
        }
    }
}

nonisolated struct LoginTestResult: Codable, Sendable, Identifiable {
    let id: String
    let success: Bool
    let duration: TimeInterval
    let errorMessage: String?
    let responseDetail: String?
    let testedAt: Date

    init(success: Bool, duration: TimeInterval, errorMessage: String? = nil, responseDetail: String? = nil) {
        self.id = UUID().uuidString
        self.success = success
        self.duration = duration
        self.errorMessage = errorMessage
        self.responseDetail = responseDetail
        self.testedAt = Date()
    }
}
