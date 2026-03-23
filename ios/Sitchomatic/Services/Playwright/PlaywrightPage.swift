import Foundation
import WebKit

nonisolated enum NavigationWaitCondition: String, Sendable {
    case load
    case domContentLoaded
    case networkIdle
}

nonisolated enum LocatorState: String, Sendable {
    case visible
    case hidden
    case attached
}

nonisolated enum TraceCategory: String, Sendable {
    case navigation
    case action
    case evaluate
    case screenshot
    case wait
    case assertion
    case system
}

nonisolated struct TraceEntry: Sendable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let category: TraceCategory
    let message: String
    let pageID: UUID

    var formatted: String {
        let ms = Int(timestamp.timeIntervalSince1970 * 1000) % 100000
        return "[\(ms)] [\(category.rawValue)] \(message)"
    }
}

nonisolated enum PlaywrightError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case navigationFailed(String)
    case timeout(String)
    case elementNotFound(String)
    case elementNotVisible(String)
    case elementNotInteractable(String)
    case javaScriptError(String)
    case screenshotFailed(String)
    case assertionFailed(String)
    case pageDisposed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .navigationFailed(let reason): "Navigation failed: \(reason)"
        case .timeout(let detail): "Timeout: \(detail)"
        case .elementNotFound(let selector): "Element not found: \(selector)"
        case .elementNotVisible(let selector): "Element not visible: \(selector)"
        case .elementNotInteractable(let selector): "Element not interactable: \(selector)"
        case .javaScriptError(let detail): "JavaScript error: \(detail)"
        case .screenshotFailed(let detail): "Screenshot failed: \(detail)"
        case .assertionFailed(let detail): "Assertion failed: \(detail)"
        case .pageDisposed: "Page has been disposed"
        }
    }
}

@MainActor
final class PlaywrightPage: Identifiable {
    let id: UUID
    let webView: WKWebView
    let defaultTimeout: TimeInterval

    private(set) var tracingEnabled: Bool = false
    private var traceLog: [TraceEntry] = []
    private var networkIdleInjected: Bool = false
    private let navigationDelegate: PageNavigationDelegate
    private weak var orchestrator: PlaywrightOrchestrator?

    private var speedMode: SpeedMode {
        orchestrator?.currentSpeedMode ?? .balanced
    }

    init(webView: WKWebView, id: UUID, defaultTimeout: TimeInterval = 30.0, orchestrator: PlaywrightOrchestrator? = nil) {
        self.webView = webView
        self.id = id
        self.defaultTimeout = defaultTimeout
        self.orchestrator = orchestrator
        self.navigationDelegate = PageNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    func goto(_ urlString: String, waitUntil: NavigationWaitCondition = .load, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        guard let url = URL(string: urlString) else {
            throw PlaywrightError.invalidURL(urlString)
        }

        trace(.navigation, "goto(\(urlString))")
        navigationDelegate.reset()
        networkIdleInjected = false
        webView.load(URLRequest(url: url))
        try await waitForNavigation(condition: waitUntil, timeout: effectiveTimeout)
        trace(.navigation, "goto complete — \(webView.url?.absoluteString ?? "unknown")")
    }

    func reload(waitUntil: NavigationWaitCondition = .load, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        trace(.navigation, "reload()")
        navigationDelegate.reset()
        networkIdleInjected = false
        webView.reload()
        try await waitForNavigation(condition: waitUntil, timeout: effectiveTimeout)
    }

    func goBack() async throws {
        trace(.navigation, "goBack()")
        navigationDelegate.reset()
        networkIdleInjected = false
        webView.goBack()
        try await waitForNavigation(condition: .load, timeout: defaultTimeout)
    }

    func goForward() async throws {
        trace(.navigation, "goForward()")
        navigationDelegate.reset()
        networkIdleInjected = false
        webView.goForward()
        try await waitForNavigation(condition: .load, timeout: defaultTimeout)
    }

    func waitForLoadState(_ condition: NavigationWaitCondition, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        trace(.wait, "waitForLoadState(\(condition.rawValue))")
        try await waitForNavigation(condition: condition, timeout: effectiveTimeout)
    }

    func waitForTimeout(_ ms: Int) async throws {
        trace(.wait, "waitForTimeout(\(ms)ms)")
        try await Task.sleep(for: .milliseconds(ms))
    }

    func waitForPostActionSettle(timeout: TimeInterval? = nil) async {
        let effectiveTimeout = timeout ?? 2.5
        let networkIdleTimeout = min(effectiveTimeout, 2.0)
        let domTimeout = min(effectiveTimeout, 1.5)

        _ = try? await waitForLoadState(.domContentLoaded, timeout: domTimeout)
        _ = try? await waitForLoadState(.networkIdle, timeout: networkIdleTimeout)
        if speedMode.postSubmitSettleMs > 0 {
            try? await Task.sleep(for: .milliseconds(speedMode.postSubmitSettleMs))
        }
    }

    func waitForURLChange(from previousURL: String, timeout: TimeInterval? = nil) async -> Bool {
        let effectiveTimeout = timeout ?? defaultTimeout
        let deadline = Date().addingTimeInterval(effectiveTimeout)
        let normalizedPreviousURL = previousURL.lowercased()

        while Date() < deadline {
            let currentURL = url().lowercased()
            if !currentURL.isEmpty && currentURL != normalizedPreviousURL {
                return true
            }
            try? await Task.sleep(for: .milliseconds(speedMode.actionabilityPollMs))
        }

        return false
    }

    func currentReadyState() async -> String {
        ((try? await evaluate("document.readyState")) as String?) ?? "loading"
    }

    func bodyText() async throws -> String {
        try await evaluate(
            """
            (function() {
                var body = document.body;
                if (!body) return '';
                return body.innerText || body.textContent || '';
            })()
            """
        )
    }

    func locator(_ selector: String, timeout: TimeInterval? = nil) -> Locator {
        Locator(page: self, selector: selector, timeout: timeout ?? defaultTimeout)
    }

    func getByRole(_ role: String, name: String? = nil) -> Locator {
        var selector = "[\(roleAttribute(role))]"
        if let name {
            selector = "[\(roleAttribute(role))][aria-label=\"\(name)\"], [\(roleAttribute(role))]:has-text(\"\(name)\")"
        }
        return Locator(page: self, selector: selector, timeout: defaultTimeout)
    }

    func getByText(_ text: String, exact: Bool = false) -> Locator {
        let selector = exact ? ":text-is(\"\(text)\")" : ":text(\"\(text)\")"
        return Locator(page: self, selector: selector, timeout: defaultTimeout, textFilter: text)
    }

    func getByPlaceholder(_ text: String) -> Locator {
        Locator(page: self, selector: "[placeholder=\"\(text)\"]", timeout: defaultTimeout)
    }

    func getByLabel(_ text: String) -> Locator {
        Locator(page: self, selector: "[aria-label=\"\(text)\"], label:has-text(\"\(text)\") + input, label:has-text(\"\(text)\") + select", timeout: defaultTimeout)
    }

    func getByTestId(_ testId: String) -> Locator {
        Locator(page: self, selector: "[data-testid=\"\(testId)\"]", timeout: defaultTimeout)
    }

    func expect(_ locator: Locator) -> Expectation {
        Expectation(locator: locator, page: self)
    }

    func evaluate<T>(_ script: String) async throws -> T {
        trace(.evaluate, "evaluate(\(String(script.prefix(80)))...)")
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.javaScriptError(error.localizedDescription))
                } else if let typed = result as? T {
                    continuation.resume(returning: typed)
                } else if result == nil, let nilResult = Optional<Any>.none as? T {
                    continuation.resume(returning: nilResult)
                } else {
                    let desc = result.map { String(describing: $0) } ?? "nil"
                    continuation.resume(throwing: PlaywrightError.javaScriptError("Type mismatch — got \(desc)"))
                }
            }
        }
    }

    func evaluateVoid(_ script: String) async throws {
        trace(.evaluate, "evaluateVoid(\(String(script.prefix(60)))...)")
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == "WKJavaScriptExceptionDomain" || nsError.code == 5 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: PlaywrightError.javaScriptError(error.localizedDescription))
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func screenshot() async throws -> Data {
        trace(.screenshot, "screenshot()")
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Int(webView.frame.width))

        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.screenshotFailed(error.localizedDescription))
                } else if let image, let data = image.pngData() {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PlaywrightError.screenshotFailed("No image data"))
                }
            }
        }
    }

    func url() -> String {
        webView.url?.absoluteString ?? ""
    }

    func title() async throws -> String {
        try await evaluate("document.title")
    }

    func close() {
        orchestrator?.closePage(self)
    }

    func startTracing() {
        tracingEnabled = true
        traceLog.removeAll()
        trace(.system, "Tracing started")
    }

    func stopTracing() -> [TraceEntry] {
        trace(.system, "Tracing stopped — \(traceLog.count) entries")
        tracingEnabled = false
        let log = traceLog
        traceLog.removeAll()
        return log
    }

    func trace(_ category: TraceCategory, _ message: String) {
        guard tracingEnabled else { return }
        traceLog.append(TraceEntry(
            timestamp: Date(),
            category: category,
            message: message,
            pageID: id
        ))
    }

    private func injectNetworkIdleMonitor() async throws {
        if networkIdleInjected {
            let alreadyInstalled: Bool = ((try? await evaluate("Boolean(window.__pwNetworkMonitor)")) as Bool?) ?? false
            if alreadyInstalled {
                return
            }
            networkIdleInjected = false
        }

        let monitorJS = """
        (function() {
            if (window.__pwNetworkMonitor) return true;
            window.__pwNetworkMonitor = { pending: 0, lastActivity: Date.now() };
            var monitor = window.__pwNetworkMonitor;

            var originalFetch = window.fetch;
            if (typeof originalFetch === 'function') {
                window.fetch = function() {
                    monitor.pending += 1;
                    monitor.lastActivity = Date.now();
                    return originalFetch.apply(this, arguments).finally(function() {
                        monitor.pending = Math.max(0, monitor.pending - 1);
                        monitor.lastActivity = Date.now();
                    });
                };
            }

            var originalOpen = XMLHttpRequest.prototype.open;
            var originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function() {
                this.__pwTracked = true;
                return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                if (this.__pwTracked) {
                    monitor.pending += 1;
                    monitor.lastActivity = Date.now();
                    this.addEventListener('loadend', function() {
                        monitor.pending = Math.max(0, monitor.pending - 1);
                        monitor.lastActivity = Date.now();
                    });
                }
                return originalSend.apply(this, arguments);
            };

            return true;
        })()
        """

        let deadline = Date().addingTimeInterval(3)
        var lastError: Error?

        while Date() < deadline {
            do {
                let installed: Bool = try await evaluate(monitorJS)
                if installed {
                    networkIdleInjected = true
                    return
                }
            } catch {
                lastError = error
            }

            try await Task.sleep(for: .milliseconds(speedMode.actionabilityPollMs))
        }

        throw lastError ?? PlaywrightError.javaScriptError("Failed to install network idle monitor")
    }

    private func waitForNavigation(condition: NavigationWaitCondition, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        let pollIntervalMs = speedMode.actionabilityPollMs

        while Date() < deadline {
            if let navigationError = navigationDelegate.navigationError {
                throw PlaywrightError.navigationFailed(navigationError.localizedDescription)
            }

            let satisfied: Bool
            switch condition {
            case .load:
                satisfied = navigationDelegate.didFinishLoad
            case .domContentLoaded:
                let readyState = await currentReadyState()
                satisfied = readyState == "interactive" || readyState == "complete"
            case .networkIdle:
                if !navigationDelegate.didFinishLoad {
                    satisfied = false
                } else {
                    _ = try? await injectNetworkIdleMonitor()
                    let readyState = await currentReadyState()
                    let isIdle = (try? await networkIsIdle()) ?? false
                    satisfied = isIdle || readyState == "complete"
                }
            }

            if satisfied {
                if speedMode.postSubmitSettleMs > 0 {
                    try await Task.sleep(for: .milliseconds(speedMode.postSubmitSettleMs))
                }
                return
            }

            try await Task.sleep(for: .milliseconds(pollIntervalMs))
        }

        throw PlaywrightError.timeout("Navigation timed out after \(Int(timeout))s (condition: \(condition.rawValue))")
    }

    private func networkIsIdle() async throws -> Bool {
        let quietWindowMs = max(500, speedMode.postSubmitPollMs)
        let idleCheck = """
        (function() {
            var monitor = window.__pwNetworkMonitor;
            if (!monitor) return document.readyState === 'complete';
            return monitor.pending === 0 && (Date.now() - monitor.lastActivity) >= \(quietWindowMs);
        })()
        """
        return try await evaluate(idleCheck)
    }

    private func roleAttribute(_ role: String) -> String {
        switch role.lowercased() {
        case "button": return "role=\"button\""
        case "link": return "role=\"link\""
        case "textbox": return "role=\"textbox\""
        case "checkbox": return "role=\"checkbox\""
        case "heading": return "role=\"heading\""
        case "img", "image": return "role=\"img\""
        case "navigation": return "role=\"navigation\""
        case "dialog": return "role=\"dialog\""
        case "tab": return "role=\"tab\""
        case "listbox": return "role=\"listbox\""
        case "option": return "role=\"option\""
        case "menuitem": return "role=\"menuitem\""
        case "radio": return "role=\"radio\""
        case "slider": return "role=\"slider\""
        case "switch": return "role=\"switch\""
        case "alert": return "role=\"alert\""
        default: return "role=\"\(role)\""
        }
    }
}

private final class PageNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinishLoad: Bool = false
    var navigationError: Error?

    func reset() {
        didFinishLoad = false
        navigationError = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.navigationError = error
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.navigationError = error
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
}
