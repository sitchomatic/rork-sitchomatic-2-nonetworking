import Foundation

nonisolated enum SessionVisibilityFilter: String, Hashable, CaseIterable, Sendable {
    case all
    case active
    case success
    case noAccount
    case permDisabled
    case tempDisabled
    case unsure
    case error

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .success: "Success"
        case .noAccount: "No ACC"
        case .permDisabled: "Perm"
        case .tempDisabled: "Temp"
        case .unsure: "Review"
        case .error: "Error"
        }
    }

    var iconName: String {
        switch self {
        case .all: "square.stack.fill"
        case .active: "bolt.fill"
        case .success: "checkmark.seal.fill"
        case .noAccount: "person.slash.fill"
        case .permDisabled: "lock.slash.fill"
        case .tempDisabled: "clock.badge.exclamationmark.fill"
        case .unsure: "questionmark.diamond.fill"
        case .error: "exclamationmark.octagon.fill"
        }
    }
}
