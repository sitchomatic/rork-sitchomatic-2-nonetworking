import Foundation
import UIKit

@MainActor
final class BackgroundTaskService {
    static let shared = BackgroundTaskService()

    private var activeTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var keepAliveTasks: [String: Task<Void, Never>] = [:]
    private let logger = DebugLogger.shared

    private(set) var remainingBackgroundTime: TimeInterval = 0
    private(set) var isBackgroundTimeLow: Bool = false
    private var timeMonitorTask: Task<Void, Never>?

    private let lowTimeThresholdSeconds: TimeInterval = 15

    private init() {}

    func beginBackgroundTask(identifier: String, expirationHandler: @escaping @Sendable () -> Void) {
        if let existing = activeTasks[identifier], existing != .invalid {
            return
        }

        let taskID = UIApplication.shared.beginBackgroundTask(withName: identifier) { [weak self] in
            expirationHandler()
            Task { @MainActor in
                self?.endBackgroundTask(identifier: identifier)
            }
        }

        if taskID != .invalid {
            activeTasks[identifier] = taskID
            logger.log("Background task started: \(identifier)", category: .automation, level: .info)
            startKeepAlive(for: identifier, expirationHandler: expirationHandler)
            startTimeMonitor()
        } else {
            logger.log("Failed to start background task: \(identifier)", category: .automation, level: .warning)
        }
    }

    func endBackgroundTask(identifier: String) {
        keepAliveTasks[identifier]?.cancel()
        keepAliveTasks.removeValue(forKey: identifier)

        guard let taskID = activeTasks[identifier], taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        activeTasks.removeValue(forKey: identifier)
        logger.log("Background task ended: \(identifier)", category: .automation, level: .info)

        if activeTasks.isEmpty {
            stopTimeMonitor()
        }
    }

    func endAllTasks() {
        for (_, task) in keepAliveTasks {
            task.cancel()
        }
        keepAliveTasks.removeAll()

        for (identifier, taskID) in activeTasks where taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            logger.log("Background task force-ended: \(identifier)", category: .automation, level: .warning)
        }
        activeTasks.removeAll()
        stopTimeMonitor()
    }

    var activeTaskCount: Int { activeTasks.count }
    var hasActiveTasks: Bool { !activeTasks.isEmpty }

    private func startKeepAlive(for identifier: String, expirationHandler: @escaping @Sendable () -> Void) {
        keepAliveTasks[identifier]?.cancel()
        keepAliveTasks[identifier] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }

                guard let self else { break }
                let remaining = UIApplication.shared.backgroundTimeRemaining
                if remaining < self.lowTimeThresholdSeconds && remaining != .greatestFiniteMagnitude {
                    self.logger.log("Background time critical (\(String(format: "%.0f", remaining))s) — refreshing task: \(identifier)", category: .automation, level: .warning)

                    self.endBackgroundTask(identifier: identifier)
                    self.beginBackgroundTask(identifier: identifier, expirationHandler: expirationHandler)
                    break
                }
            }
        }
    }

    private func startTimeMonitor() {
        guard timeMonitorTask == nil else { return }
        timeMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { break }
                let remaining = UIApplication.shared.backgroundTimeRemaining
                self.remainingBackgroundTime = remaining == .greatestFiniteMagnitude ? 999 : remaining
                self.isBackgroundTimeLow = self.remainingBackgroundTime < self.lowTimeThresholdSeconds
            }
        }
    }

    private func stopTimeMonitor() {
        timeMonitorTask?.cancel()
        timeMonitorTask = nil
        remainingBackgroundTime = 0
        isBackgroundTimeLow = false
    }

    var diagnosticSummary: String {
        let timeStr = remainingBackgroundTime > 900 ? "foreground" : "\(String(format: "%.0f", remainingBackgroundTime))s"
        return "Tasks: \(activeTaskCount) | BG time: \(timeStr) | Low: \(isBackgroundTimeLow)"
    }
}
