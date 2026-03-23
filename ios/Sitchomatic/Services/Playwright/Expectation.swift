import Foundation

@MainActor
final class Expectation {

    private let locator: Locator
    private let page: PlaywrightPage
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval = 0.2
    private var negated: Bool = false

    init(locator: Locator, page: PlaywrightPage, timeout: TimeInterval = 10.0) {
        self.locator = locator
        self.page = page
        self.timeout = timeout
    }

    var not: Expectation {
        let exp = Expectation(locator: locator, page: page, timeout: timeout)
        exp.negated = !negated
        return exp
    }

    func toBeVisible(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toBeVisible(\(locator.selector))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let visible = (try? await locator.isVisible()) ?? false
            if negated ? !visible : visible { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) NOT to be visible, but it was")
        } else {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) to be visible after \(Int(effectiveTimeout))s")
        }
    }

    func toBeHidden(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toBeHidden(\(locator.selector))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let visible = (try? await locator.isVisible()) ?? false
            if negated ? visible : !visible { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) NOT to be hidden, but it was")
        } else {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) to be hidden after \(Int(effectiveTimeout))s")
        }
    }

    func toBeEnabled(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toBeEnabled(\(locator.selector))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let enabled = (try? await locator.isEnabled()) ?? false
            if negated ? !enabled : enabled { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to be enabled")
    }

    func toBeChecked(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toBeChecked(\(locator.selector))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let checked = (try? await locator.isChecked()) ?? false
            if negated ? !checked : checked { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to be checked")
    }

    func toContainText(_ text: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toContainText(\(locator.selector), '\(String(text.prefix(40)))')")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let content = (try? await locator.textContent()) ?? ""
            let contains = content.localizedStandardContains(text)
            if negated ? !contains : contains { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.textContent()) ?? "<none>"
        if negated {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) NOT to contain '\(text)', but text was '\(String(actual.prefix(100)))'")
        } else {
            throw PlaywrightError.assertionFailed("Expected \(locator.selector) to contain '\(text)', but got '\(String(actual.prefix(100)))'")
        }
    }

    func toHaveText(_ text: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toHaveText(\(locator.selector), '\(String(text.prefix(40)))')")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let content = (try? await locator.textContent()) ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = trimmed == text
            if negated ? !matches : matches { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.textContent()) ?? "<none>"
        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to have text '\(text)', got '\(String(actual.prefix(100)))'")
    }

    func toHaveValue(_ value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toHaveValue(\(locator.selector), '\(String(value.prefix(40)))')")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let actual = (try? await locator.inputValue()) ?? ""
            let matches = actual == value
            if negated ? !matches : matches { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.inputValue()) ?? "<none>"
        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to have value '\(value)', got '\(actual)'")
    }

    func toHaveAttribute(_ name: String, value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toHaveAttribute(\(locator.selector), \(name)='\(value)')")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let actual = try? await locator.getAttribute(name)
            let matches = actual == value
            if negated ? !matches : matches { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.getAttribute(name)) ?? "<none>"
        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to have attribute \(name)='\(value)', got '\(actual)'")
    }

    func toHaveCount(_ expectedCount: Int, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.assertion, "\(negated ? "NOT " : "")toHaveCount(\(locator.selector), \(expectedCount))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let actual = (try? await locator.count()) ?? 0
            let matches = actual == expectedCount
            if negated ? !matches : matches { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.count()) ?? 0
        throw PlaywrightError.assertionFailed("Expected \(locator.selector) \(negated ? "NOT " : "")to have count \(expectedCount), got \(actual)")
    }
}
