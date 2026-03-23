import UIKit

@MainActor
final class HapticService {
    static let shared = HapticService()

    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        impactHeavy.prepare()
        impactMedium.prepare()
        notificationGenerator.prepare()
    }

    func runStart() {
        impactHeavy.impactOccurred(intensity: 1.0)
    }

    func credentialSuccess() {
        notificationGenerator.notificationOccurred(.success)
    }

    func credentialFailure() {
        notificationGenerator.notificationOccurred(.error)
    }

    func waveComplete() {
        Task { @MainActor in
            impactMedium.impactOccurred(intensity: 0.8)
            try? await Task.sleep(for: .milliseconds(120))
            impactMedium.impactOccurred(intensity: 1.0)
        }
    }

    func engineCompleted() {
        Task { @MainActor in
            notificationGenerator.notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(200))
            impactHeavy.impactOccurred(intensity: 1.0)
        }
    }

    func autoPauseWarning() {
        notificationGenerator.notificationOccurred(.warning)
    }
}
