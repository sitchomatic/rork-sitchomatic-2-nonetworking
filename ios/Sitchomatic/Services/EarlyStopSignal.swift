import Foundation

@MainActor
final class EarlyStopSignal {
    private(set) var isTriggered: Bool = false
    private(set) var triggeringSite: AutomationSite?
    private(set) var triggeringOutcome: DualLoginOutcome?

    func trigger(site: AutomationSite, outcome: DualLoginOutcome) {
        guard !isTriggered else { return }
        isTriggered = true
        triggeringSite = site
        triggeringOutcome = outcome
    }

    func reset() {
        isTriggered = false
        triggeringSite = nil
        triggeringOutcome = nil
    }
}
