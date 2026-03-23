import Foundation

@MainActor
final class SiteLoginAutomationService {
    static let shared = SiteLoginAutomationService()

    private let logger: DebugLogger = .shared

    private init() {}

    func executeLogin(
        on page: PlaywrightPage,
        site: AutomationSite,
        credential: LoginCredential,
        speedMode: SpeedMode,
        overrideURL: String? = nil
    ) async throws -> DualLoginOutcome {
        let loginURL: String = normalizedURL(overrideURL, fallback: site.defaultLoginURL)
        let selectorSummary: String = site.loginFormSelectors.joined(separator: " | ")

        page.trace(.system, "Site login start — site: \(site.rawValue), url: \(loginURL)")
        logger.log(
            "Starting \(site.displayName) login for \(credential.displayName) using selectors: \(selectorSummary)",
            category: .automation,
            level: .info
        )

        do {
            try await page.goto(
                loginURL,
                waitUntil: .domContentLoaded,
                timeout: speedMode.navigationTimeoutSeconds
            )
            await page.waitForPostActionSettle(timeout: min(3.0, speedMode.navigationTimeoutSeconds))

            let usernameMatch = try await resolveFirstAvailableSelector(
                site.usernameSelectors,
                on: page,
                timeout: speedMode.selectorTimeoutSeconds
            )
            let passwordMatch = try await resolveFirstAvailableSelector(
                site.passwordSelectors,
                on: page,
                timeout: speedMode.selectorTimeoutSeconds
            )
            let submitMatch = try await resolveFirstAvailableSelector(
                site.submitSelectors,
                on: page,
                timeout: speedMode.selectorTimeoutSeconds
            )

            page.trace(
                .action,
                "Resolved selectors — username: \(usernameMatch.selector), password: \(passwordMatch.selector), submit: \(submitMatch.selector)"
            )

            try await usernameMatch.locator.fill(credential.username)
            try await passwordMatch.locator.fill(credential.password)

            let previousURL: String = page.url()
            try await submitMatch.locator.click()

            let outcome: DualLoginOutcome = try await observePostSubmitOutcome(
                on: page,
                site: site,
                loginURL: loginURL,
                previousURL: previousURL,
                submitSelector: submitMatch.selector,
                speedMode: speedMode
            )

            page.trace(.assertion, "Site login classified as \(outcome.rawValue) for \(site.rawValue)")
            return outcome
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PlaywrightError {
            switch error {
            case .invalidURL, .navigationFailed:
                logger.log(
                    "\(site.displayName) navigation failure: \(error.localizedDescription)",
                    category: .automation,
                    level: .error
                )
                return .error
            case .timeout(let message):
                logger.log(
                    "\(site.displayName) timeout: \(message)",
                    category: .automation,
                    level: .warning
                )
                return .tempDisabled
            case .pageDisposed:
                return .error
            case .elementNotFound, .elementNotInteractable, .elementNotVisible:
                logger.log(
                    "\(site.displayName) selector failure: \(error.localizedDescription)",
                    category: .automation,
                    level: .error
                )
                return .unsure
            case .javaScriptError, .screenshotFailed, .assertionFailed:
                return .error
            }
        } catch {
            logger.log(
                "\(site.displayName) unexpected login error: \(error.localizedDescription)",
                category: .automation,
                level: .error
            )
            return .unsure
        }
    }

    private func resolveFirstAvailableSelector(
        _ selectors: [String],
        on page: PlaywrightPage,
        timeout: TimeInterval
    ) async throws -> SelectorMatch {
        let deadline: Date = Date().addingTimeInterval(timeout)
        let perSelectorTimeout: TimeInterval = min(1.0, timeout)

        while Date() < deadline {
            for selector in selectors {
                let locator: Locator = page.locator(selector, timeout: timeout)
                do {
                    try await locator.waitFor(state: .visible, timeout: perSelectorTimeout)
                    return SelectorMatch(selector: selector, locator: locator)
                } catch {
                    let attached = (try? await locator.count()) ?? 0
                    if attached > 0 {
                        return SelectorMatch(selector: selector, locator: locator)
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(120))
        }

        throw PlaywrightError.elementNotFound(selectors.joined(separator: " | "))
    }

    private func observePostSubmitOutcome(
        on page: PlaywrightPage,
        site: AutomationSite,
        loginURL: String,
        previousURL: String,
        submitSelector: String,
        speedMode: SpeedMode
    ) async throws -> DualLoginOutcome {
        let observationDeadline: Date = Date().addingTimeInterval(speedMode.postSubmitObservationSeconds)
        var urlChanged: Bool = false
        var lastObservedText: String = ""
        var submitStillVisible: Bool = true

        await page.waitForPostActionSettle(timeout: 2.0)

        while Date() < observationDeadline {
            if !urlChanged {
                urlChanged = await page.waitForURLChange(from: previousURL, timeout: 0.6)
            }

            let pageText: String = (try? await page.bodyText()) ?? ""
            lastObservedText = pageText.lowercased()
            submitStillVisible = (try? await page.locator(submitSelector).isVisible()) ?? false

            let outcome: DualLoginOutcome = classifyOutcome(
                site: site,
                loginURL: loginURL,
                currentURL: page.url().lowercased(),
                pageText: lastObservedText,
                submitStillVisible: submitStillVisible,
                urlChanged: urlChanged
            )

            if outcome != .unsure {
                return outcome
            }

            try await Task.sleep(for: .milliseconds(speedMode.postSubmitPollMs))
        }

        return classifyFinalOutcome(
            site: site,
            loginURL: loginURL,
            currentURL: page.url().lowercased(),
            pageText: lastObservedText,
            submitStillVisible: submitStillVisible,
            urlChanged: urlChanged
        )
    }

    private func classifyOutcome(
        site: AutomationSite,
        loginURL: String,
        currentURL: String,
        pageText: String,
        submitStillVisible: Bool,
        urlChanged: Bool
    ) -> DualLoginOutcome {
        if containsAny(site.invalidCredentialTextHints, in: pageText) {
            return .noAccount
        }

        if containsAny(site.permanentFailureTextHints, in: pageText) {
            return .permDisabled
        }

        if containsAny(site.temporaryFailureTextHints, in: pageText) {
            return .tempDisabled
        }

        let normalizedLoginURL: String = normalizedURL(loginURL, fallback: site.defaultLoginURL).lowercased()
        let movedAwayFromLogin: Bool = !site.matchesLoginURL(currentURL) && currentURL != normalizedLoginURL
        let successHintPresent: Bool = containsAny(site.successTextHints, in: pageText)

        if successHintPresent || movedAwayFromLogin || (urlChanged && !submitStillVisible) {
            return .success
        }

        return .unsure
    }

    private func classifyFinalOutcome(
        site: AutomationSite,
        loginURL: String,
        currentURL: String,
        pageText: String,
        submitStillVisible: Bool,
        urlChanged: Bool
    ) -> DualLoginOutcome {
        let provisional = classifyOutcome(
            site: site,
            loginURL: loginURL,
            currentURL: currentURL,
            pageText: pageText,
            submitStillVisible: submitStillVisible,
            urlChanged: urlChanged
        )
        if provisional != .unsure {
            return provisional
        }

        if submitStillVisible {
            return .unsure
        }

        return .tempDisabled
    }

    private func containsAny(_ hints: [String], in text: String) -> Bool {
        hints.contains { text.contains($0) }
    }

    private func normalizedURL(_ value: String?, fallback: String) -> String {
        let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? fallback : trimmedValue
    }
}

private struct SelectorMatch {
    let selector: String
    let locator: Locator
}
