import Foundation

nonisolated enum TestingStrategy: String, Sendable, CaseIterable, Codable {
    case original
    case threePasswords

    var displayName: String {
        switch self {
        case .original: "Original Strategy"
        case .threePasswords: "3 Passwords Strategy"
        }
    }

    var shortName: String {
        switch self {
        case .original: "Original"
        case .threePasswords: "3-Pass"
        }
    }

    var iconName: String {
        switch self {
        case .original: "shield.checkered"
        case .threePasswords: "key.2.on.ring"
        }
    }

    var accentColorName: String {
        switch self {
        case .original: "cyan"
        case .threePasswords: "green"
        }
    }

    var description: String {
        switch self {
        case .original:
            "Wave-based single password. Each email tested with its primary password across both sites in parallel. 4 registered attempts per site required. Early-stop and burn rules enforced. No Account = 4 incorrect on both sites."
        case .threePasswords:
            "Password-phased optimal ordering. Phase 1 tests P1 for all emails, Phase 2 tests P2 for survivors, Phase 3 tests P3 for remaining. Minimises total clicks by eliminating resolved emails early."
        }
    }

    var detailedRules: [String] {
        switch self {
        case .original:
            [
                "Each email uses its primary password only",
                "Both sites tested in parallel per email",
                "4 fully registered attempts per site required",
                "Page load + JS settlement verified before each attempt",
                "Login button colour-reversion wait (up to 6s)",
                "Early-Stop: disabled on either site → halt both",
                "Burn Rule: permDisabled or success → burn IP/viewport/fingerprint",
                "No Account: 4× incorrect on BOTH sites, zero disabled messages",
                "Temp Disabled: 100% account exists (positive signal)"
            ]
        case .threePasswords:
            [
                "Phase 1: Test P1 for ALL emails (both sites parallel)",
                "Decisive result → email DONE, skip P2 & P3",
                "Phase 2: Only surviving emails get P2 tested",
                "Phase 3: Only remaining emails get P3 tested",
                "No Account: ALL passwords exhausted with only incorrect",
                "Early-Stop + Burn rules same as Original",
                "Optimal ordering minimises total site interactions",
                "~60-70% fewer clicks vs flat approach"
            ]
        }
    }
}
