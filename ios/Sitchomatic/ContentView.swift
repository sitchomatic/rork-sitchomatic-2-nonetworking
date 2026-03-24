import SwiftUI

struct ContentView: View {
    @State private var showSplash: Bool = true

    var body: some View {
        if showSplash {
            SplashMenuView {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
            .transition(.opacity)
        } else {
            MainMenuView()
                .transition(.opacity)
        }
    }
}
