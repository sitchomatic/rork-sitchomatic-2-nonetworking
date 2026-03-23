import Foundation

nonisolated enum AutomationSite: String, Sendable, CaseIterable, Codable, Identifiable {
    case joe
    case ignition

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .joe:
            "Joe Fortune"
        case .ignition:
            "Ignition Casino"
        }
    }

    var defaultLoginURL: String {
        switch self {
        case .joe:
            "https://www.joefortunepokies.win/login"
        case .ignition:
            "https://www.ignitioncasino.ooo/?overlay=login"
        }
    }

    var loginURLHints: [String] {
        switch self {
        case .joe:
            ["/login", "joefortunepokies.win/login"]
        case .ignition:
            ["overlay=login", "ignitioncasino.ooo", "/login"]
        }
    }

    var usernameSelectors: [String] {
        switch self {
        case .joe:
            [
                "#username",
                "input[name='username']",
                "input[id='username']",
                "input[type='email'][name='username']",
                "form input[type='email']"
            ]
        case .ignition:
            [
                "#email",
                "input[name='email']",
                "input[id='email']",
                "form input[type='text']#email",
                "form input[type='text'][name='email']"
            ]
        }
    }

    var passwordSelectors: [String] {
        switch self {
        case .joe:
            [
                "#password",
                "input[name='password']",
                "input[id='password']",
                "form input[type='password']"
            ]
        case .ignition:
            [
                "#login-password",
                "input[name='password']",
                "input[id='login-password']",
                "form input[type='password']"
            ]
        }
    }

    var submitSelectors: [String] {
        switch self {
        case .joe:
            [
                "#loginSubmit",
                "button#loginSubmit",
                "button[type='submit']",
                "form button.ol-responsive-button--variant_primary"
            ]
        case .ignition:
            [
                "#login-submit",
                "button#login-submit",
                "button[type='submit'].custom-cta.primary.cta-large.full-opacity",
                "button[type='submit']"
            ]
        }
    }

    var loginFormSelectors: [String] {
        usernameSelectors + passwordSelectors + submitSelectors
    }

    var successTextHints: [String] {
        switch self {
        case .joe:
            ["cashier", "deposit", "withdraw", "my account", "logout", "log out"]
        case .ignition:
            ["cashier", "deposit", "withdraw", "rewards", "messages", "logout", "log out"]
        }
    }

    var invalidCredentialTextHints: [String] {
        [
            "incorrect",
            "invalid",
            "unable to log in",
            "unable to login",
            "login failed",
            "does not match"
        ]
    }

    var temporaryFailureTextHints: [String] {
        [
            "temporarily disabled",
            "temporarily locked",
            "try again later",
            "too many attempts",
            "too many failed attempts",
            "verification required",
            "security check",
            "captcha",
            "two-factor",
            "2fa"
        ]
    }

    var permanentFailureTextHints: [String] {
        [
            "permanently disabled",
            "account disabled",
            "account closed",
            "account suspended",
            "account locked",
            "self-excluded",
            "restricted account"
        ]
    }

    func matchesLoginURL(_ url: String) -> Bool {
        let lowercasedURL: String = url.lowercased()
        return loginURLHints.contains { lowercasedURL.contains($0) }
    }
}
