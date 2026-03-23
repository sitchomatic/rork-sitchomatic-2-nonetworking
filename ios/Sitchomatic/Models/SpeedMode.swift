import Foundation

nonisolated enum SpeedMode: String, Sendable, CaseIterable, Codable {
    case speedDemon
    case balanced
    case slowDebug
    case maxConcurrency

    var displayName: String {
        switch self {
        case .speedDemon: "Speed Demon"
        case .balanced: "Balanced"
        case .slowDebug: "Slow Debug"
        case .maxConcurrency: "Max Concurrency"
        }
    }

    var typingDelayMs: Int {
        switch self {
        case .speedDemon: 15
        case .balanced: 50
        case .slowDebug: 150
        case .maxConcurrency: 25
        }
    }

    var actionDelayMs: Int {
        switch self {
        case .speedDemon: 100
        case .balanced: 500
        case .slowDebug: 2000
        case .maxConcurrency: 200
        }
    }

    var postSubmitWaitMs: Int {
        switch self {
        case .speedDemon: 500
        case .balanced: 2000
        case .slowDebug: 5000
        case .maxConcurrency: 1000
        }
    }

    var maxConcurrentPairs: Int {
        switch self {
        case .speedDemon: 8
        case .balanced: 6
        case .slowDebug: 2
        case .maxConcurrency: 12
        }
    }

    var humanVarianceRange: ClosedRange<Int> {
        switch self {
        case .speedDemon: 5...20
        case .balanced: 20...80
        case .slowDebug: 50...200
        case .maxConcurrency: 10...30
        }
    }

    var navigationTimeoutSeconds: TimeInterval {
        switch self {
        case .speedDemon: 18
        case .balanced: 25
        case .slowDebug: 40
        case .maxConcurrency: 20
        }
    }

    var selectorTimeoutSeconds: TimeInterval {
        switch self {
        case .speedDemon: 8
        case .balanced: 12
        case .slowDebug: 20
        case .maxConcurrency: 9
        }
    }

    var postSubmitObservationSeconds: TimeInterval {
        switch self {
        case .speedDemon: 5
        case .balanced: 9
        case .slowDebug: 16
        case .maxConcurrency: 6
        }
    }

    var postSubmitPollMs: Int {
        switch self {
        case .speedDemon: 125
        case .balanced: 175
        case .slowDebug: 250
        case .maxConcurrency: 125
        }
    }

    var postSubmitSettleMs: Int {
        switch self {
        case .speedDemon: 200
        case .balanced: 450
        case .slowDebug: 900
        case .maxConcurrency: 250
        }
    }

    var actionabilityPollMs: Int {
        switch self {
        case .speedDemon: 60
        case .balanced: 90
        case .slowDebug: 140
        case .maxConcurrency: 70
        }
    }

    var requiredStableActionPolls: Int {
        switch self {
        case .speedDemon: 2
        case .balanced: 2
        case .slowDebug: 3
        case .maxConcurrency: 2
        }
    }

    var maximumActionRetries: Int {
        switch self {
        case .speedDemon: 2
        case .balanced: 3
        case .slowDebug: 4
        case .maxConcurrency: 3
        }
    }

    func typingDelayWithVariance() -> Int {
        let variance = Int.random(in: humanVarianceRange)
        return typingDelayMs + variance
    }

    func actionDelayWithVariance() -> Int {
        let variance = Int.random(in: humanVarianceRange)
        return actionDelayMs + variance
    }

    var iconName: String {
        switch self {
        case .speedDemon: "hare.fill"
        case .balanced: "gauge.with.dots.needle.50percent"
        case .slowDebug: "tortoise.fill"
        case .maxConcurrency: "bolt.horizontal.fill"
        }
    }

    var description: String {
        switch self {
        case .speedDemon: "Fastest execution, minimal delays"
        case .balanced: "Human-like timing with moderate delays"
        case .slowDebug: "Extra slow for debugging and observation"
        case .maxConcurrency: "Optimized for maximum parallel sessions"
        }
    }
}
