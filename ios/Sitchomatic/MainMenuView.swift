import SwiftUI

struct MainMenuView: View {
    @State private var selectedTab: AppTab = .dashboard
    @State private var logger = DebugLogger.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "circle.hexagongrid.fill", value: AppTab.dashboard) {
                NavigationStack {
                    DashboardView(selectedTab: $selectedTab)
                }
            }

            Tab("Runs", systemImage: "bolt.horizontal.fill", value: AppTab.run) {
                NavigationStack {
                    DualRunView()
                }
            }

            Tab("Credentials", systemImage: "person.2.fill", value: AppTab.credentials) {
                NavigationStack {
                    CredentialManagerView()
                }
            }

            Tab("Debug", systemImage: "ant.fill", value: AppTab.debug) {
                NavigationStack {
                    DebugContainerView()
                }
            }
            .badge(logger.recentErrors.isEmpty ? 0 : logger.recentErrors.count)

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tint(NeonTheme.neonGreen)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}
