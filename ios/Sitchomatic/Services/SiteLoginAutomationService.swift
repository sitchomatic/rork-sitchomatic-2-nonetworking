import Foundation

@MainActor
final class SiteLoginAutomationService {
    static let shared = SiteLoginAutomationService()

    private let logger: DebugLogger = .shared
    private let settings: AutomationSettings = .shared

    private init() {}

    func executeLogin(
        on page: PlaywrightPage,
        site: AutomationSite,
        credential: LoginCredential,
        speedMode: SpeedMode,
        overrideURL: String? = nil,
        earlyStopSignal: EarlyStopSignal? = nil
    ) async throws -> DualLoginOutcome {
        let loginURL: String = normalizedURL(overrideURL, fallback: site.defaultLoginURL)
        let maxAttempts = settings.maxAttemptsPerSite

        page.trace(.system, "Site login start — site: \(site.rawValue), url: \(loginURL), maxAttempts: \(maxAttempts)")
        logger.log(
            "Starting \(site.displayName) login for \(credential.displayName) — \(maxAttempts) attempts max",
            category: .automation,
            level: .info
        )

        do {
            try await page.goto(
                loginURL,
                waitUntil: .domContentLoaded,
                timeout: speedMode.navigationTimeoutSeconds
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.log(
                "\(site.displayName) navigation failure: \(error.localizedDescription)",
                category: .automation,
                level: .error
            )
            return .error
        }

        let readinessOK = await waitForFullPageReadiness(
            on: page,
            site: site,
            speedMode: speedMode
        )
        if !readinessOK {
            logger.log("\(site.displayName) page readiness timeout", category: .automation, level: .warning)
            return .error
        }

        var registeredAttempts = 0
        var unregisteredRetries = 0
        let maxUnregisteredRetries = 3

        while registeredAttempts < maxAttempts {
            if Task.isCancelled { throw CancellationError() }

            if let signal = earlyStopSignal, signal.isTriggered {
                page.trace(.system, "Early-stop signal received from \(signal.triggeringSite?.rawValue ?? "unknown") — halting \(site.rawValue)")
                logger.log(
                    "\(site.displayName) early-stopped by cross-site signal (\(signal.triggeringOutcome?.shortName ?? "unknown"))",
                    category: .automation,
                    level: .info
                )
                return signal.triggeringOutcome == .permDisabled ? .permDisabled : .tempDisabled
            }

            if registeredAttempts > 0 {
                let interAttemptReadiness = await waitForFormReadiness(on: page, site: site, speedMode: speedMode)
                if !interAttemptReadiness {
                    unregisteredRetries += 1
                    if unregisteredRetries >= maxUnregisteredRetries {
                        return .error
                    }
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
            }

            let usernameMatch: SelectorMatch
            let passwordMatch: SelectorMatch
            let submitMatch: SelectorMatch
            do {
                usernameMatch = try await resolveFirstAvailableSelector(
                    site.usernameSelectors, on: page, timeout: speedMode.selectorTimeoutSeconds
                )
                passwordMatch = try await resolveFirstAvailableSelector(
                    site.passwordSelectors, on: page, timeout: speedMode.selectorTimeoutSeconds
                )
                submitMatch = try await resolveFirstAvailableSelector(
                    site.submitSelectors, on: page, timeout: speedMode.selectorTimeoutSeconds
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.log("\(site.displayName) selector resolution failed: \(error.localizedDescription)", category: .automation, level: .error)
                return .unsure
            }

            try await usernameMatch.locator.clear()
            try await usernameMatch.locator.fill(credential.username)
            try await passwordMatch.locator.clear()
            try await passwordMatch.locator.fill(credential.password)

            let originalColor = await getButtonColor(on: page, selector: submitMatch.selector)
            page.trace(.action, "Submit button original color: \(originalColor ?? "unknown")")

            try await submitMatch.locator.click()

            let attemptResult = await observeButtonCycleAndOutcome(
                on: page,
                site: site,
                submitSelector: submitMatch.selector,
                originalColor: originalColor,
                speedMode: speedMode
            )

            switch attemptResult {
            case .registered(let outcome):
                registeredAttempts += 1
                page.trace(.assertion, "Attempt \(registeredAttempts)/\(maxAttempts) registered — outcome: \(outcome.rawValue)")

                switch outcome {
                case .permDisabled:
                    earlyStopSignal?.trigger(site: site, outcome: .permDisabled)
                    return .permDisabled
                case .tempDisabled:
                    earlyStopSignal?.trigger(site: site, outcome: .tempDisabled)
                    return .tempDisabled
                case .success:
                    return .success
                case .noAccount:
                    if registeredAttempts >= maxAttempts {
                        return .noAccount
                    }
                    continue
                case .unsure, .error:
                    if registeredAttempts >= maxAttempts {
                        return outcome
                    }
                    continue
                }

            case .unregistered:
                unregisteredRetries += 1
                page.trace(.system, "Attempt unregistered (button never cycled) — retry \(unregisteredRetries)/\(maxUnregisteredRetries)")
                if unregisteredRetries >= maxUnregisteredRetries {
                    return .error
                }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
        }

        return .noAccount
    }

    // MARK: - Full Page Readiness (Gap 3)

    private func waitForFullPageReadiness(
        on page: PlaywrightPage,
        site: AutomationSite,
        speedMode: SpeedMode
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(speedMode.navigationTimeoutSeconds)

        await page.waitForPostActionSettle(timeout: min(3.0, speedMode.navigationTimeoutSeconds))

        while Date() < deadline {
            if Task.isCancelled { return false }

            let networkIdle = await checkNetworkIdle(on: page)
            let domStable = await checkDOMStability(on: page)
            let elementsReady = await checkLoginElementsInteractive(on: page, site: site, timeout: 1.0)

            if networkIdle && domStable && elementsReady {
                page.trace(.system, "Page readiness confirmed — network idle, DOM stable, elements interactive")
                return true
            }

            try? await Task.sleep(for: .milliseconds(300))
        }

        let elementsReady = await checkLoginElementsInteractive(on: page, site: site, timeout: 2.0)
        if elementsReady {
            page.trace(.system, "Page readiness partial — elements interactive (network/DOM may still be settling)")
            return true
        }

        return false
    }

    private func checkNetworkIdle(on page: PlaywrightPage) async -> Bool {
        let js = """
        (function() {
            var monitor = window.__pwNetworkMonitor;
            if (!monitor) return document.readyState === 'complete';
            return monitor.pending === 0 && (Date.now() - monitor.lastActivity) >= 500;
        })()
        """
        return ((try? await page.evaluate(js)) as Bool?) ?? false
    }

    private func checkDOMStability(on page: PlaywrightPage) async -> Bool {
        let lengthJS = "(document.body && document.body.innerHTML.length) || 0"
        let firstLength: Int = ((try? await page.evaluate(lengthJS)) as Int?) ?? 0
        try? await Task.sleep(for: .milliseconds(300))
        let secondLength: Int = ((try? await page.evaluate(lengthJS)) as Int?) ?? 0
        return firstLength > 0 && firstLength == secondLength
    }

    private func checkLoginElementsInteractive(
        on page: PlaywrightPage,
        site: AutomationSite,
        timeout: TimeInterval
    ) async -> Bool {
        let usernameSelector = site.usernameSelectors.first ?? ""
        let passwordSelector = site.passwordSelectors.first ?? ""
        let submitSelector = site.submitSelectors.first ?? ""

        let js = """
        (function() {
            function isInteractive(sel) {
                if (!sel) return false;
                var el = document.querySelector(sel);
                if (!el) return false;
                var rect = el.getBoundingClientRect();
                if (rect.width === 0 || rect.height === 0) return false;
                var style = window.getComputedStyle(el);
                if (style.display === 'none' || style.visibility === 'hidden') return false;
                if (el.disabled || el.readOnly) return false;
                return true;
            }
            return isInteractive('\(usernameSelector.replacingOccurrences(of: "'", with: "\\'"))') &&
                   isInteractive('\(passwordSelector.replacingOccurrences(of: "'", with: "\\'"))') &&
                   isInteractive('\(submitSelector.replacingOccurrences(of: "'", with: "\\'"))');
        })()
        """
        return ((try? await page.evaluate(js)) as Bool?) ?? false
    }

    private func waitForFormReadiness(
        on page: PlaywrightPage,
        site: AutomationSite,
        speedMode: SpeedMode
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(min(6.0, speedMode.selectorTimeoutSeconds))
        while Date() < deadline {
            if await checkLoginElementsInteractive(on: page, site: site, timeout: 1.0) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    // MARK: - Button Color Detection (Gap 2)

    private func getButtonColor(on page: PlaywrightPage, selector: String) async -> String? {
        let js = """
        (function() {
            var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (!el) return null;
            return window.getComputedStyle(el).backgroundColor;
        })()
        """
        return (try? await page.evaluate(js)) as String?
    }

    private func observeButtonCycleAndOutcome(
        on page: PlaywrightPage,
        site: AutomationSite,
        submitSelector: String,
        originalColor: String?,
        speedMode: SpeedMode
    ) async -> AttemptResult {
        let maxWaitForChange: TimeInterval = 6.0
        let maxWaitForRevert: TimeInterval = 6.0

        var colorChanged = false
        var changeDeadline = Date().addingTimeInterval(maxWaitForChange)

        if let original = originalColor {
            while Date() < changeDeadline {
                if Task.isCancelled { return .unregistered }
                try? await Task.sleep(for: .milliseconds(200))

                let currentColor = await getButtonColor(on: page, selector: submitSelector)

                let pageText: String = ((try? await page.bodyText()) ?? "").lowercased()
                let earlyOutcome = classifyFromText(site: site, pageText: pageText)
                if earlyOutcome != .unsure {
                    return .registered(earlyOutcome)
                }

                if let current = currentColor, current != original {
                    colorChanged = true
                    page.trace(.action, "Button color changed: \(original) → \(current)")
                    break
                }
            }

            if colorChanged {
                let revertDeadline = Date().addingTimeInterval(maxWaitForRevert)
                while Date() < revertDeadline {
                    if Task.isCancelled { return .unregistered }
                    try? await Task.sleep(for: .milliseconds(200))

                    let currentColor = await getButtonColor(on: page, selector: submitSelector)

                    let pageText: String = ((try? await page.bodyText()) ?? "").lowercased()
                    let textOutcome = classifyFromText(site: site, pageText: pageText)
                    if textOutcome != .unsure {
                        page.trace(.assertion, "Red text detected during button revert wait: \(textOutcome.rawValue)")
                        return .registered(textOutcome)
                    }

                    if let current = currentColor, current == original {
                        page.trace(.action, "Button reverted to original color")
                        let finalText: String = ((try? await page.bodyText()) ?? "").lowercased()
                        let finalOutcome = classifyFromText(site: site, pageText: finalText)
                        return .registered(finalOutcome == .unsure ? .noAccount : finalOutcome)
                    }
                }

                let finalText: String = ((try? await page.bodyText()) ?? "").lowercased()
                let finalOutcome = classifyFromText(site: site, pageText: finalText)
                if finalOutcome != .unsure {
                    return .registered(finalOutcome)
                }
                return .unregistered
            }
        }

        let fallbackOutcome = await fallbackPostSubmitObservation(
            on: page,
            site: site,
            speedMode: speedMode
        )
        if fallbackOutcome != .unsure {
            return .registered(fallbackOutcome)
        }

        return .unregistered
    }

    private func fallbackPostSubmitObservation(
        on page: PlaywrightPage,
        site: AutomationSite,
        speedMode: SpeedMode
    ) async -> DualLoginOutcome {
        let deadline = Date().addingTimeInterval(speedMode.postSubmitObservationSeconds)
        while Date() < deadline {
            if Task.isCancelled { return .unsure }
            let pageText: String = ((try? await page.bodyText()) ?? "").lowercased()
            let outcome = classifyFromText(site: site, pageText: pageText)
            if outcome != .unsure {
                return outcome
            }

            let currentURL = page.url().lowercased()
            let normalizedLogin = site.defaultLoginURL.lowercased()
            if !site.matchesLoginURL(currentURL) && currentURL != normalizedLogin {
                if containsAny(site.successTextHints, in: pageText) {
                    return .success
                }
            }

            try? await Task.sleep(for: .milliseconds(speedMode.postSubmitPollMs))
        }
        return .unsure
    }

    // MARK: - Classification

    private func classifyFromText(site: AutomationSite, pageText: String) -> DualLoginOutcome {
        if containsAny(site.permanentFailureTextHints, in: pageText) {
            return .permDisabled
        }
        if containsAny(site.temporaryFailureTextHints, in: pageText) {
            return .tempDisabled
        }
        if containsAny(site.invalidCredentialTextHints, in: pageText) {
            return .noAccount
        }
        if containsAny(site.successTextHints, in: pageText) {
            return .success
        }
        return .unsure
    }

    // MARK: - Selector Resolution

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

    // MARK: - Helpers

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

private enum AttemptResult {
    case registered(DualLoginOutcome)
    case unregistered
}
