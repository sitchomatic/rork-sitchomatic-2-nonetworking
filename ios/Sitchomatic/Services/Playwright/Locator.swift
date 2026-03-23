import Foundation
import WebKit

nonisolated struct LocatorSnapshot: Sendable {
    let isFound: Bool
    let isVisible: Bool
    let isEnabled: Bool
    let isEditable: Bool
    let receivesEvents: Bool
    let rectSignature: String
}

@MainActor
final class Locator {
    let selector: String

    private let page: PlaywrightPage
    private let timeout: TimeInterval
    private let parentSelector: String?
    private let nthIndex: Int?
    private let textFilter: String?

    private var speedMode: SpeedMode {
        PlaywrightOrchestrator.shared.currentSpeedMode
    }

    private var pollIntervalMs: Int {
        speedMode.actionabilityPollMs
    }

    private var maxRetries: Int {
        speedMode.maximumActionRetries
    }

    init(
        page: PlaywrightPage,
        selector: String,
        timeout: TimeInterval = 30.0,
        parentSelector: String? = nil,
        nthIndex: Int? = nil,
        textFilter: String? = nil
    ) {
        self.page = page
        self.selector = selector
        self.timeout = timeout
        self.parentSelector = parentSelector
        self.nthIndex = nthIndex
        self.textFilter = textFilter
    }

    func click(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "click(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: false)
            try await self.humanDelay(self.speedMode.actionDelayWithVariance())

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    el.scrollIntoView({behavior: 'instant', block: 'center', inline: 'nearest'});
                    el.click();
                    return JSON.stringify({success: true});
                })()
                """
            )
            _ = try self.parseActionResult(result)
        }

        await page.waitForPostActionSettle(timeout: 2.0)
    }

    func fill(_ value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        let escapedValue = escapedJavaScriptString(value)
        page.trace(.action, "fill(\(selector), '\(String(value.prefix(40)))')")

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: true)
            try await self.humanDelay(self.speedMode.actionDelayWithVariance())

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    el.focus();
                    if (typeof el.select === 'function') { el.select(); }
                    el.value = '';
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.value = '\(escapedValue)';
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                    return JSON.stringify({success: true, value: el.value || ''});
                })()
                """
            )
            let parsed = try self.parseActionResult(result)
            let filledValue = parsed["value"] as? String ?? ""
            guard filledValue == value else {
                throw PlaywrightError.assertionFailed("Expected \(self.selector) to be filled with the provided value")
            }
        }

        await page.waitForPostActionSettle(timeout: 1.0)
    }

    func clear(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "clear(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: true)

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    el.focus();
                    if (typeof el.select === 'function') { el.select(); }
                    el.value = '';
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                    return JSON.stringify({success: true, value: el.value || ''});
                })()
                """
            )
            let parsed = try self.parseActionResult(result)
            let currentValue = parsed["value"] as? String ?? ""
            guard currentValue.isEmpty else {
                throw PlaywrightError.assertionFailed("Expected \(self.selector) to be cleared")
            }
        }
    }

    func type(_ text: String, delay: Int? = nil, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        let effectiveDelay = delay ?? speedMode.typingDelayMs
        page.trace(.action, "type(\(selector), '\(String(text.prefix(40)))', delay: \(effectiveDelay)ms)")

        _ = try await waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: true)

        let focusResult: String = try await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                el.focus();
                return JSON.stringify({success: true});
            })()
            """
        )
        _ = try parseActionResult(focusResult)

        for character in text {
            let characterString = String(character)

            if characterString == "Enter" || characterString == "\n" {
                try await page.evaluateVoid(
                    """
                    (function() {
                        \(resolveElementJS())
                        if (!el) return;
                        var eventPayload = {key: 'Enter', code: 'Enter', bubbles: true, cancelable: true};
                        el.dispatchEvent(new KeyboardEvent('keydown', eventPayload));
                        el.dispatchEvent(new KeyboardEvent('keypress', eventPayload));
                        var form = el.closest('form');
                        if (form) {
                            form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
                        }
                        el.dispatchEvent(new KeyboardEvent('keyup', eventPayload));
                    })()
                    """
                )
            } else {
                let escapedCharacter = escapedJavaScriptString(characterString)
                try await page.evaluateVoid(
                    """
                    (function() {
                        \(resolveElementJS())
                        if (!el) return;
                        var key = '\(escapedCharacter)';
                        el.dispatchEvent(new KeyboardEvent('keydown', {key: key, bubbles: true}));
                        el.dispatchEvent(new KeyboardEvent('keypress', {key: key, bubbles: true}));
                        el.value = (el.value || '') + key;
                        el.dispatchEvent(new Event('input', {bubbles: true}));
                        el.dispatchEvent(new KeyboardEvent('keyup', {key: key, bubbles: true}));
                    })()
                    """
                )
            }

            let variance = Int.random(in: speedMode.humanVarianceRange)
            try await Task.sleep(for: .milliseconds(effectiveDelay + variance))
        }

        await page.waitForPostActionSettle(timeout: 1.0)
    }

    func check(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "check(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: false)

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    if (!el.checked) { el.click(); }
                    return JSON.stringify({success: true, checked: !!el.checked});
                })()
                """
            )
            let parsed = try self.parseActionResult(result)
            let isChecked = parsed["checked"] as? Bool ?? false
            guard isChecked else {
                throw PlaywrightError.assertionFailed("Expected \(self.selector) to become checked")
            }
        }

        await page.waitForPostActionSettle(timeout: 1.0)
    }

    func uncheck(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "uncheck(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: false)

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    if (el.checked) { el.click(); }
                    return JSON.stringify({success: true, checked: !!el.checked});
                })()
                """
            )
            let parsed = try self.parseActionResult(result)
            let isChecked = parsed["checked"] as? Bool ?? false
            guard !isChecked else {
                throw PlaywrightError.assertionFailed("Expected \(self.selector) to become unchecked")
            }
        }

        await page.waitForPostActionSettle(timeout: 1.0)
    }

    func selectOption(_ value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "selectOption(\(selector), '\(value)')")
        let escapedValue = escapedJavaScriptString(value)

        try await retryAction(timeout: effectiveTimeout) {
            _ = try await self.waitForActionable(timeout: effectiveTimeout, requireReceivingEvents: true, requireEditable: false)

            let result: String = try await self.page.evaluate(
                """
                (function() {
                    \(self.resolveElementJS())
                    if (!el) return JSON.stringify({error: 'not_found'});
                    el.value = '\(escapedValue)';
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    return JSON.stringify({success: true, value: el.value || ''});
                })()
                """
            )
            let parsed = try self.parseActionResult(result)
            let selectedValue = parsed["value"] as? String ?? ""
            guard selectedValue == value else {
                throw PlaywrightError.assertionFailed("Expected \(self.selector) to select the provided option")
            }
        }

        await page.waitForPostActionSettle(timeout: 1.0)
    }

    func isVisible() async throws -> Bool {
        let snapshot = try await readSnapshot()
        return snapshot.isVisible
    }

    func isEnabled() async throws -> Bool {
        let snapshot = try await readSnapshot()
        return snapshot.isEnabled
    }

    func isChecked() async throws -> Bool {
        let result: Bool = (try? await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return false;
                return !!el.checked;
            })()
            """
        )) ?? false
        return result
    }

    func textContent() async throws -> String {
        try await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return '';
                return el.textContent || '';
            })()
            """
        )
    }

    func innerText() async throws -> String {
        try await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return '';
                return el.innerText || '';
            })()
            """
        )
    }

    func inputValue() async throws -> String {
        try await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return '';
                return el.value || '';
            })()
            """
        )
    }

    func getAttribute(_ name: String) async throws -> String? {
        let escapedName = escapedJavaScriptString(name)
        return try? await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) return null;
                return el.getAttribute('\(escapedName)');
            })()
            """
        ) as String
    }

    func count() async throws -> Int {
        let result: Int = (try? await page.evaluate(countScript())) ?? 0
        return result
    }

    func first() -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: 0, textFilter: textFilter)
    }

    func last() -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: -1, textFilter: textFilter)
    }

    func nth(_ index: Int) -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: index, textFilter: textFilter)
    }

    func filter(hasText: String) -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: nthIndex, textFilter: hasText)
    }

    func locator(_ childSelector: String) -> Locator {
        Locator(page: page, selector: childSelector, timeout: timeout, parentSelector: selector)
    }

    func waitFor(state: LocatorState = .visible, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.wait, "waitFor(\(selector), state: \(state.rawValue))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            switch state {
            case .visible:
                if (try? await isVisible()) == true {
                    return
                }
            case .hidden:
                if (try? await isVisible()) == false {
                    return
                }
            case .attached:
                let snapshot = try await readSnapshot()
                if snapshot.isFound {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(pollIntervalMs))
        }

        throw PlaywrightError.timeout("waitFor(\(selector), \(state.rawValue)) timed out after \(Int(effectiveTimeout))s")
    }

    func resolveElementJS() -> String {
        var js = ""
        let escapedParentSelector = parentSelector?.replacingOccurrences(of: "'", with: "\\'")

        if let escapedParentSelector {
            js += "var parent = document.querySelector('\(escapedParentSelector)');\n"
            js += "if (!parent) { var el = null; } else {\n"
        }

        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        let scope = parentSelector != nil ? "parent" : "document"

        if let textFilter {
            let escapedText = textFilter.replacingOccurrences(of: "'", with: "\\'")
            js += "var allEls = \(scope).querySelectorAll('\(escapedSelector)');\n"
            js += "var el = null;\n"
            js += "for (var i = 0; i < allEls.length; i++) {\n"
            js += "  var text = allEls[i].innerText || allEls[i].textContent || '';\n"
            js += "  if (text.indexOf('\(escapedText)') !== -1) { el = allEls[i]; break; }\n"
            js += "}\n"
        } else if let nthIndex {
            js += "var allEls = \(scope).querySelectorAll('\(escapedSelector)');\n"
            if nthIndex == -1 {
                js += "var el = allEls.length > 0 ? allEls[allEls.length - 1] : null;\n"
            } else {
                js += "var el = allEls.length > \(nthIndex) ? allEls[\(nthIndex)] : null;\n"
            }
        } else {
            js += "var el = \(scope).querySelector('\(escapedSelector)');\n"
        }

        if parentSelector != nil {
            js += "}\n"
        }

        return js
    }

    private func countScript() -> String {
        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        if let parentSelector {
            let escapedParentSelector = parentSelector.replacingOccurrences(of: "'", with: "\\'")
            if let textFilter {
                let escapedText = textFilter.replacingOccurrences(of: "'", with: "\\'")
                return """
                (function() {
                    var parent = document.querySelector('\(escapedParentSelector)');
                    if (!parent) return 0;
                    var allEls = parent.querySelectorAll('\(escapedSelector)');
                    var count = 0;
                    for (var i = 0; i < allEls.length; i++) {
                        var text = allEls[i].innerText || allEls[i].textContent || '';
                        if (text.indexOf('\(escapedText)') !== -1) { count += 1; }
                    }
                    return count;
                })()
                """
            }
            return """
            (function() {
                var parent = document.querySelector('\(escapedParentSelector)');
                if (!parent) return 0;
                return parent.querySelectorAll('\(escapedSelector)').length;
            })()
            """
        }

        if let textFilter {
            let escapedText = textFilter.replacingOccurrences(of: "'", with: "\\'")
            return """
            (function() {
                var allEls = document.querySelectorAll('\(escapedSelector)');
                var count = 0;
                for (var i = 0; i < allEls.length; i++) {
                    var text = allEls[i].innerText || allEls[i].textContent || '';
                    if (text.indexOf('\(escapedText)') !== -1) { count += 1; }
                }
                return count;
            })()
            """
        }

        return """
        (function() {
            return document.querySelectorAll('\(escapedSelector)').length;
        })()
        """
    }

    private func waitForActionable(
        timeout: TimeInterval,
        requireReceivingEvents: Bool,
        requireEditable: Bool
    ) async throws -> LocatorSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        var lastRectSignature: String?
        var stablePolls: Int = 0

        while Date() < deadline {
            do {
                let snapshot = try await readSnapshot()

                guard snapshot.isFound else {
                    stablePolls = 0
                    lastRectSignature = nil
                    lastError = PlaywrightError.elementNotFound(selector)
                    try await Task.sleep(for: .milliseconds(pollIntervalMs))
                    continue
                }

                guard snapshot.isVisible else {
                    stablePolls = 0
                    lastRectSignature = nil
                    lastError = PlaywrightError.elementNotVisible(selector)
                    try await Task.sleep(for: .milliseconds(pollIntervalMs))
                    continue
                }

                guard snapshot.isEnabled else {
                    stablePolls = 0
                    lastRectSignature = nil
                    lastError = PlaywrightError.elementNotInteractable(selector)
                    try await Task.sleep(for: .milliseconds(pollIntervalMs))
                    continue
                }

                if requireEditable && !snapshot.isEditable {
                    stablePolls = 0
                    lastRectSignature = nil
                    lastError = PlaywrightError.elementNotInteractable(selector)
                    try await Task.sleep(for: .milliseconds(pollIntervalMs))
                    continue
                }

                if requireReceivingEvents && !snapshot.receivesEvents {
                    stablePolls = 0
                    lastRectSignature = nil
                    lastError = PlaywrightError.elementNotInteractable(selector)
                    try await Task.sleep(for: .milliseconds(pollIntervalMs))
                    continue
                }

                if snapshot.rectSignature == lastRectSignature {
                    stablePolls += 1
                } else {
                    stablePolls = 1
                    lastRectSignature = snapshot.rectSignature
                }

                if stablePolls >= speedMode.requiredStableActionPolls {
                    return snapshot
                }
            } catch {
                stablePolls = 0
                lastRectSignature = nil
                lastError = error
            }

            try await Task.sleep(for: .milliseconds(pollIntervalMs))
        }

        throw lastError ?? PlaywrightError.timeout("Element \(selector) not actionable after \(Int(timeout))s")
    }

    private func readSnapshot() async throws -> LocatorSnapshot {
        let result: String = try await page.evaluate(
            """
            (function() {
                \(resolveElementJS())
                if (!el) {
                    return JSON.stringify({
                        found: false,
                        visible: false,
                        enabled: false,
                        editable: false,
                        receivesEvents: false,
                        rectSignature: 'missing'
                    });
                }

                var rect = el.getBoundingClientRect();
                var style = window.getComputedStyle(el);
                var visible = rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && style.opacity !== '0';
                var enabled = !el.disabled && el.getAttribute('aria-disabled') !== 'true' && style.pointerEvents !== 'none';
                var editable = !el.disabled && !el.readOnly;
                var maxX = Math.max(0, (window.innerWidth || document.documentElement.clientWidth || 1) - 1);
                var maxY = Math.max(0, (window.innerHeight || document.documentElement.clientHeight || 1) - 1);
                var cx = Math.min(Math.max(rect.left + rect.width / 2, 0), maxX);
                var cy = Math.min(Math.max(rect.top + rect.height / 2, 0), maxY);
                var pointEl = document.elementFromPoint(cx, cy);
                var receivesEvents = !!pointEl && (pointEl === el || el.contains(pointEl) || pointEl.contains(el));
                var rectSignature = [Math.round(rect.left), Math.round(rect.top), Math.round(rect.width), Math.round(rect.height)].join(',');

                return JSON.stringify({
                    found: true,
                    visible: visible,
                    enabled: enabled,
                    editable: editable,
                    receivesEvents: receivesEvents,
                    rectSignature: rectSignature
                });
            })()
            """
        )

        let parsed = try parseActionResult(result)
        return LocatorSnapshot(
            isFound: parsed["found"] as? Bool ?? false,
            isVisible: parsed["visible"] as? Bool ?? false,
            isEnabled: parsed["enabled"] as? Bool ?? false,
            isEditable: parsed["editable"] as? Bool ?? false,
            receivesEvents: parsed["receivesEvents"] as? Bool ?? false,
            rectSignature: parsed["rectSignature"] as? String ?? "missing"
        )
    }

    private func retryAction(timeout: TimeInterval, action: () async throws -> Void) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                try await action()
                return
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let backoffMs = pollIntervalMs * (attempt + 1)
                    try await Task.sleep(for: .milliseconds(backoffMs))
                }
            }
        }
        throw lastError ?? PlaywrightError.timeout("Action on \(selector) failed after \(maxRetries) retries")
    }

    func parseActionResult(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaywrightError.javaScriptError("Failed to parse action result: \(json)")
        }

        if let error = dictionary["error"] as? String {
            switch error {
            case "not_found":
                throw PlaywrightError.elementNotFound(selector)
            case "not_visible":
                throw PlaywrightError.elementNotVisible(selector)
            default:
                throw PlaywrightError.javaScriptError(error)
            }
        }

        return dictionary
    }

    private func escapedJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func humanDelay(_ ms: Int) async throws {
        guard ms > 0 else { return }
        try await Task.sleep(for: .milliseconds(ms))
    }
}
