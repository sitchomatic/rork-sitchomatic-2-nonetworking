import UIKit

@Observable
final class BackgroundTaskService {
    static let shared = BackgroundTaskService()

    private(set) var isKeepingAwake: Bool = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var activeRunners: Int = 0
    private var renewalTask: Task<Void, Never>?

    func registerRunner() {
        activeRunners += 1
        if activeRunners == 1 {
            enableNoSleep()
            beginBackgroundTask()
            startRenewalChain()
        }
    }

    func unregisterRunner() {
        activeRunners = max(0, activeRunners - 1)
        if activeRunners == 0 {
            disableNoSleep()
            endBackgroundTask()
            renewalTask?.cancel()
            renewalTask = nil
        }
    }

    var runnerCount: Int { activeRunners }

    private func enableNoSleep() {
        UIApplication.shared.isIdleTimerDisabled = true
        isKeepingAwake = true
    }

    private func disableNoSleep() {
        UIApplication.shared.isIdleTimerDisabled = false
        isKeepingAwake = false
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SitchomaticAutomation") { [weak self] in
            self?.renewBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func renewBackgroundTask() {
        let oldTask = backgroundTaskID
        backgroundTaskID = .invalid

        if activeRunners > 0 {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SitchomaticAutomation") { [weak self] in
                self?.renewBackgroundTask()
            }
        }

        if oldTask != .invalid {
            UIApplication.shared.endBackgroundTask(oldTask)
        }
    }

    private func startRenewalChain() {
        renewalTask?.cancel()
        renewalTask = Task {
            while !Task.isCancelled && activeRunners > 0 {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, activeRunners > 0 else { break }
                renewBackgroundTask()
            }
        }
    }
}
