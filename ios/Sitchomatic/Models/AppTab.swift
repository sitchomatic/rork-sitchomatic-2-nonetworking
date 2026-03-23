import Foundation

nonisolated enum AppTab: String, Hashable, CaseIterable, Sendable {
    case dashboard
    case run
    case credentials
    case debug
    case settings
}
