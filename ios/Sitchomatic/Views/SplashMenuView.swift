import SwiftUI

struct SplashMenuView: View {
    let onContinue: () -> Void

    @State private var appeared: Bool = false
    @State private var buttonVisible: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("MainMenuWallpaper")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()

                    Button {
                        onContinue()
                    } label: {
                        HStack(spacing: 6) {
                            Text("ENTER")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                        .overlay(
                            Capsule()
                                .stroke(NeonTheme.neonGreen.opacity(0.5), lineWidth: 0.5)
                        )
                        .neonGlow(NeonTheme.neonGreen, radius: 3)
                    }
                    .opacity(buttonVisible ? 1 : 0)
                    .offset(y: buttonVisible ? 0 : -10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                appeared = true
            }
            withAnimation(.spring(duration: 0.5).delay(0.6)) {
                buttonVisible = true
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: buttonVisible)
    }
}
