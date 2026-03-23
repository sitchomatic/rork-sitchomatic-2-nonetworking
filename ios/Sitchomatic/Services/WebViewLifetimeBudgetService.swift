import Foundation

@MainActor
final class WebViewLifetimeBudgetService {
    static let shared = WebViewLifetimeBudgetService()

    private(set) var totalWebViewsCreated: Int = 0
    private(set) var totalWebViewsDestroyed: Int = 0
    private(set) var peakConcurrent: Int = 0
    private(set) var waveCreations: Int = 0
    private(set) var waveDestructions: Int = 0
    private let maxLifetimeWebViews: Int = 500
    private let baseMaxConcurrent: Int = 24
    private let logger = DebugLogger.shared

    private init() {}

    var currentConcurrent: Int { totalWebViewsCreated - totalWebViewsDestroyed }
    var lifetimeBudgetRemaining: Int { maxLifetimeWebViews - totalWebViewsCreated }
    var isOverBudget: Bool { totalWebViewsCreated >= maxLifetimeWebViews }

    var effectiveMaxConcurrent: Int {
        let crashProtection = CrashProtectionService.shared
        let memoryLevel = crashProtection.memoryPressureLevel
        return min(baseMaxConcurrent, memoryLevel.suggestedMaxConcurrency * 2)
    }

    var isConcurrentLimitReached: Bool { currentConcurrent >= effectiveMaxConcurrent }

    func recordCreation() -> Bool {
        guard !isOverBudget else {
            logger.log("WebView lifetime budget EXHAUSTED (\(totalWebViewsCreated)/\(maxLifetimeWebViews))", category: .webView, level: .critical)
            return false
        }
        guard !isConcurrentLimitReached else {
            logger.log("Concurrent limit reached (\(currentConcurrent)/\(effectiveMaxConcurrent))", category: .webView, level: .warning)
            return false
        }
        totalWebViewsCreated += 1
        waveCreations += 1
        peakConcurrent = max(peakConcurrent, currentConcurrent)
        return true
    }

    func recordDestruction() {
        totalWebViewsDestroyed += 1
        waveDestructions += 1
    }

    func beginNewWave() {
        waveCreations = 0
        waveDestructions = 0
    }

    func reset() {
        totalWebViewsCreated = 0
        totalWebViewsDestroyed = 0
        peakConcurrent = 0
        waveCreations = 0
        waveDestructions = 0
    }

    var waveNetCreations: Int { waveCreations - waveDestructions }

    var diagnosticSummary: String {
        "Lifetime: \(totalWebViewsCreated)/\(maxLifetimeWebViews) | Concurrent: \(currentConcurrent)/\(effectiveMaxConcurrent) | Peak: \(peakConcurrent) | Wave: +\(waveCreations)/-\(waveDestructions)"
    }
}
