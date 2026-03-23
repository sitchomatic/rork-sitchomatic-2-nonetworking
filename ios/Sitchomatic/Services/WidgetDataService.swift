import Foundation
import WidgetKit

nonisolated struct WidgetSharedData: Codable, Sendable {
    var engineState: String
    var succeededCount: Int
    var failedCount: Int
    var noAccountCount: Int
    var permDisabledCount: Int
    var tempDisabledCount: Int
    var unsureCount: Int
    var errorCount: Int
    var totalSessions: Int
    var currentWave: Int
    var totalWaves: Int
    var overallProgress: Double
    var healthScore: Double
    var lastUpdated: Date

    static let defaultData = WidgetSharedData(
        engineState: "Idle",
        succeededCount: 0,
        failedCount: 0,
        noAccountCount: 0,
        permDisabledCount: 0,
        tempDisabledCount: 0,
        unsureCount: 0,
        errorCount: 0,
        totalSessions: 0,
        currentWave: 0,
        totalWaves: 0,
        overallProgress: 0,
        healthScore: 1.0,
        lastUpdated: Date()
    )
}

@MainActor
final class WidgetDataService {
    static let shared = WidgetDataService()
    private let suiteName = "group.app.rork.sitchomatic"
    private let dataKey = "widgetSharedData"

    private init() {}

    func persist(_ data: WidgetSharedData) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: dataKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateFromEngine(_ engine: ConcurrentAutomationEngine) {
        let data = WidgetSharedData(
            engineState: engine.state.displayName,
            succeededCount: engine.succeededCount,
            failedCount: engine.failedCount,
            noAccountCount: engine.noAccountCount,
            permDisabledCount: engine.permDisabledCount,
            tempDisabledCount: engine.tempDisabledCount,
            unsureCount: engine.unsureCount,
            errorCount: engine.errorCount,
            totalSessions: engine.sessions.count,
            currentWave: engine.currentWave,
            totalWaves: engine.totalWaves,
            overallProgress: engine.overallProgress,
            healthScore: engine.healthScore,
            lastUpdated: Date()
        )
        persist(data)
    }

    nonisolated func load() -> WidgetSharedData {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: dataKey),
              let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: data) else {
            return .defaultData
        }
        return decoded
    }
}
