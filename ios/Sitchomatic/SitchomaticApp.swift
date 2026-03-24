import SwiftUI

@main
struct SitchomaticApp: App {
    @State private var orchestrator = PlaywrightOrchestrator.shared
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var settings = AutomationSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    WebViewPool.shared.handleMemoryPressure()
                    CrashProtectionService.shared.recordCrash()
                }
                .onOpenURL { url in
                    NordVPNRotationService.shared.handleCallbackURL(url)
                }
        }
    }
}
