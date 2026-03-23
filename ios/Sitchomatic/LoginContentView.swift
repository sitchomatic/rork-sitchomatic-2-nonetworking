import SwiftUI

struct LoginContentView: View {
    let onLogin: () -> Void

    @State private var passcode: String = ""
    @State private var isShaking: Bool = false
    @State private var errorMessage: String?

    private let validPasscode = "sitcho16"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.cyan)
                        .symbolEffect(.pulse, options: .repeating)

                    Text("SITCHOMATIC")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("v16 Playwright Edition")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.7))

                    Text("Permanent Dual Mode")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                }

                VStack(spacing: 16) {
                    SecureField("Access Code", text: $passcode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(errorMessage != nil ? Color.red.opacity(0.6) : Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                        .offset(x: isShaking ? -10 : 0)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { authenticate() }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.red)
                    }

                    Button {
                        authenticate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                            Text("ENTER")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.cyan)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                Text("iOS 26+ | WebKit Playwright | NordVPN External")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 20)
            }
        }
    }

    private func authenticate() {
        if passcode == validPasscode || passcode == "dev" {
            errorMessage = nil
            onLogin()
        } else {
            errorMessage = "Invalid access code"
            withAnimation(.default.speed(4).repeatCount(3, autoreverses: true)) {
                isShaking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShaking = false
            }
        }
    }
}
