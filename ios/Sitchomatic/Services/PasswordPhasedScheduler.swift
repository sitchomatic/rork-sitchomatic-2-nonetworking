import Foundation

nonisolated struct PhaseWorkItem: Sendable, Identifiable {
    let id: UUID = UUID()
    let credential: LoginCredential
    let email: String
    let passwordPhase: Int
    let totalPhases: Int
    let isFinalPhase: Bool
}

nonisolated enum PhaseOutcomeAction: Sendable {
    case resolved
    case advanceToNextPhase
    case retry
}

@Observable
@MainActor
final class PasswordPhasedScheduler {
    private(set) var emailGroups: [String: LoginCredential] = [:]
    private(set) var resolvedEmails: Set<String> = []
    private(set) var currentPhase: Int = 0
    private(set) var maxPhase: Int = 0
    private(set) var phaseResults: [Int: [String: DualLoginOutcome]] = [:]

    var totalEmails: Int { emailGroups.count }
    var resolvedCount: Int { resolvedEmails.count }
    var survivingCount: Int { totalEmails - resolvedCount }
    var isComplete: Bool { currentPhase > maxPhase || survivingCount == 0 }

    var phaseSummary: String {
        "Phase \(currentPhase + 1)/\(maxPhase + 1) — \(survivingCount) emails remaining"
    }

    func prepare(credentials: [LoginCredential]) {
        emailGroups.removeAll()
        resolvedEmails.removeAll()
        currentPhase = 0
        phaseResults.removeAll()

        for cred in credentials where cred.isEnabled {
            let key = cred.username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if var existing = emailGroups[key] {
                for pw in cred.passwords where !existing.passwords.contains(pw) {
                    existing.addPassword(pw)
                }
                emailGroups[key] = existing
            } else {
                emailGroups[key] = cred
            }
        }

        maxPhase = emailGroups.values.map { $0.passwordCount - 1 }.max() ?? 0
    }

    func workItemsForCurrentPhase() -> [PhaseWorkItem] {
        var items: [PhaseWorkItem] = []
        for (email, credential) in emailGroups {
            guard !resolvedEmails.contains(email) else { continue }
            guard currentPhase < credential.passwordCount else { continue }

            let isFinal = currentPhase >= credential.passwordCount - 1
            let phaseCredential = credential.credentialForPhase(currentPhase)

            items.append(PhaseWorkItem(
                credential: phaseCredential,
                email: email,
                passwordPhase: currentPhase,
                totalPhases: credential.passwordCount,
                isFinalPhase: isFinal
            ))
        }
        return items
    }

    func classifyPhaseOutcome(_ outcome: DualLoginOutcome, for workItem: PhaseWorkItem) -> PhaseOutcomeAction {
        if phaseResults[workItem.passwordPhase] == nil {
            phaseResults[workItem.passwordPhase] = [:]
        }
        phaseResults[workItem.passwordPhase]?[workItem.email] = outcome

        switch outcome {
        case .success, .tempDisabled, .permDisabled:
            resolvedEmails.insert(workItem.email)
            return .resolved

        case .noAccount:
            if workItem.isFinalPhase {
                resolvedEmails.insert(workItem.email)
                return .resolved
            }
            return .advanceToNextPhase

        case .error:
            return .retry

        case .unsure:
            if workItem.isFinalPhase {
                resolvedEmails.insert(workItem.email)
                return .resolved
            }
            return .advanceToNextPhase
        }
    }

    func effectiveOutcome(for workItem: PhaseWorkItem, rawOutcome: DualLoginOutcome) -> DualLoginOutcome {
        switch rawOutcome {
        case .noAccount:
            if workItem.isFinalPhase {
                return .noAccount
            }
            return .noAccount

        default:
            return rawOutcome
        }
    }

    func advancePhase() {
        currentPhase += 1
    }

    func reset() {
        emailGroups.removeAll()
        resolvedEmails.removeAll()
        currentPhase = 0
        maxPhase = 0
        phaseResults.removeAll()
    }

    func emailsResolvedInPhase(_ phase: Int) -> Int {
        phaseResults[phase]?.count ?? 0
    }

    func emailsSurvivingAfterPhase(_ phase: Int) -> Int {
        let resolvedUpToPhase = (0...phase).flatMap { phaseResults[$0]?.keys ?? [:].keys }.count
        return totalEmails - resolvedUpToPhase
    }

    func phaseEfficiencyGain() -> String {
        guard maxPhase > 0 else { return "Single password — no phasing needed" }
        let worstCase = totalEmails * (maxPhase + 1)
        let actualAttempts = (0...min(currentPhase, maxPhase)).reduce(0) { sum, phase in
            sum + (phaseResults[phase]?.count ?? 0)
        }
        guard worstCase > 0 else { return "N/A" }
        let saved = worstCase - actualAttempts
        let pct = Double(saved) / Double(worstCase) * 100
        return "\(saved) email×password combos skipped (\(String(format: "%.0f", pct))% fewer interactions)"
    }
}
