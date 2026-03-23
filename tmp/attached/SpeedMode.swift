import SwiftUI

nonisolated enum SpeedMode: String, Codable, CaseIterable, Sendable {
    case speedDemon = "Speed Demon"
    case fast = "Fast"
    case normal = "Normal"
    case slow = "Slow"
    case slowDebug = "Slow Debug"

    var icon: String {
        switch self {
        case .speedDemon: return "flame.fill"
        case .fast: return "bolt.fill"
        case .normal: return "gauge.with.dots.needle.50percent"
        case .slow: return "tortoise.fill"
        case .slowDebug: return "ladybug.fill"
        }
    }

    var color: Color {
        switch self {
        case .speedDemon: return .red
        case .fast: return .green
        case .normal: return .blue
        case .slow: return .orange
        case .slowDebug: return .indigo
        }
    }

    var typingDelayMs: Int {
        switch self {
        case .speedDemon: return 3
        case .fast: return 20
        case .normal: return 80
        case .slow: return 200
        case .slowDebug: return 500
        }
    }

    var tripleClickDelayMs: Int {
        switch self {
        case .speedDemon: return 30
        case .fast: return 80
        case .normal: return 200
        case .slow: return 400
        case .slowDebug: return 800
        }
    }

    var actionDelayMs: Int {
        switch self {
        case .speedDemon: return 50
        case .fast: return 200
        case .normal: return 600
        case .slow: return 1200
        case .slowDebug: return 2500
        }
    }

    var postSubmitWaitMs: Int {
        switch self {
        case .speedDemon: return 300
        case .fast: return 800
        case .normal: return 2000
        case .slow: return 3500
        case .slowDebug: return 6000
        }
    }

    var isDebugMode: Bool {
        self == .slowDebug
    }

    var description: String {
        switch self {
        case .speedDemon: return "Ultra fast, minimal delays"
        case .fast: return "Quick execution with short pauses"
        case .normal: return "Balanced timing for reliability"
        case .slow: return "Conservative pacing"
        case .slowDebug: return "Very slow + auto-screenshots + logging"
        }
    }
}
