import Foundation
import WebKit

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    private var inUseCount: Int = 0
    private let logger = DebugLogger.shared
    private(set) var processTerminationCount: Int = 0
    private let maxPreWarmed: Int = 3
    private(set) var preWarmCount: Int = 0
    private var preWarmedSlots: Int = 0
    private let hardCapActiveWebViews: Int = 24
    private var peakActiveCount: Int = 0
    private var totalCreated: Int = 0
    private var totalReleased: Int = 0
    private var trackedSessions: [String: TrackedWebView] = [:]
    private let staleSessionTimeoutSeconds: TimeInterval = 300
    private var staleSessionReaperTask: Task<Void, Never>?
    private var consecutiveProcessTerminations: Int = 0
    private var lastProcessTerminationTime: Date = .distantPast

    private struct TrackedWebView {
        let id: String
        let createdAt: Date
        weak var webView: WKWebView?
    }

    var activeCount: Int { inUseCount }
    var preWarmedCount: Int { preWarmedSlots }

    private init() {}

    func preWarm(count: Int = 2, stealthEnabled: Bool = true) {
        _ = stealthEnabled
        guard inUseCount < hardCapActiveWebViews else { return }
        guard !CrashProtectionService.shared.shouldReduceConcurrency else { return }

        let slots = min(count, maxPreWarmed, hardCapActiveWebViews - inUseCount)
        guard slots > 0 else { return }

        preWarmedSlots = max(preWarmedSlots, slots)
        preWarmCount += slots
    }

    enum SiteTarget: String, Sendable {
        case joe
        case ignition
    }

    func acquire(
        sessionID: String,
        stealthEnabled: Bool = true,
        viewportSize: CGSize = CGSize(width: 390, height: 844),
        target: SiteTarget = .joe
    ) async -> WKWebView {
        _ = stealthEnabled
        _ = target

        if CrashProtectionService.shared.isMemoryEmergency {
            drainPreWarmed()
            reapStaleSessions()
            _ = await CrashProtectionService.shared.waitForMemoryToDrop(timeout: 15)
        } else if CrashProtectionService.shared.isMemoryCritical {
            drainPreWarmed()
            reapStaleSessions()
            _ = await CrashProtectionService.shared.waitForMemoryToDrop(timeout: 10)
        }

        if inUseCount >= hardCapActiveWebViews {
            reapStaleSessions()
            reapDeallocatedSessions()
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(500))
                if inUseCount < hardCapActiveWebViews {
                    break
                }
            }
            if inUseCount >= hardCapActiveWebViews {
                drainPreWarmed()
                reapDeallocatedSessions()
            }
        }

        let webView = makeIsolatedWebView(viewportSize: viewportSize)
        if preWarmedSlots > 0 {
            preWarmedSlots -= 1
        }
        track(webView, sessionID: sessionID, prefix: "acq")
        return webView
    }

    func release(_ webView: WKWebView, wipeData: Bool = true) {
        guard inUseCount > 0 else {
            safeCleanupWebView(webView, wipeData: wipeData)
            return
        }
        inUseCount -= 1
        totalReleased += 1

        let matchingKey = trackedSessions.first(where: { $0.value.webView === webView })?.key
        if let key = matchingKey {
            trackedSessions.removeValue(forKey: key)
        }

        safeCleanupWebView(webView, wipeData: wipeData)
    }

    func handleMemoryPressure() {
        drainPreWarmed()
        reapStaleSessions()
        reapDeallocatedSessions()
    }

    func emergencyPurgeAll() {
        drainPreWarmed()
        reapStaleSessions()
        reapDeallocatedSessions()
        if inUseCount > hardCapActiveWebViews {
            forceResetCount()
        }
    }

    func reportProcessTermination() {
        processTerminationCount += 1
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastProcessTerminationTime)
        lastProcessTerminationTime = now

        if timeSinceLast < 30 {
            consecutiveProcessTerminations += 1
        } else {
            consecutiveProcessTerminations = 1
        }

        if consecutiveProcessTerminations >= 3 {
            drainPreWarmed()
            URLCache.shared.removeAllCachedResponses()
            consecutiveProcessTerminations = 0
        }
    }

    func drainPreWarmed() {
        preWarmedSlots = 0
    }

    func forceResetCount() {
        inUseCount = 0
        trackedSessions.removeAll()
        preWarmedSlots = 0
    }

    var diagnosticSummary: String {
        "Active: \(inUseCount)/\(hardCapActiveWebViews) | PreWarmed: \(preWarmedSlots) | Peak: \(peakActiveCount) | Created: \(totalCreated) | Released: \(totalReleased) | Crashes: \(processTerminationCount)"
    }

    private func makeIsolatedWebView(viewportSize: CGSize) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        if AutomationSettings.shared.blockUnnecessaryGraphics {
            let blockGraphicsJS = """
            (function() {
                var style = document.createElement('style');
                style.textContent = 'img, video, svg, canvas, [style*="background-image"], iframe[src*="youtube"], iframe[src*="vimeo"] { display: none !important; visibility: hidden !important; } * { background-image: none !important; }';
                (document.head || document.documentElement).appendChild(style);
                window.__sitchGraphicsBlocked = true;
            })();
            """
            let userScript = WKUserScript(
                source: blockGraphicsJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(userScript)
        }

        let webView = WKWebView(frame: CGRect(origin: .zero, size: viewportSize), configuration: configuration)
        webView.customUserAgent = generateUserAgent()
        return webView
    }

    private func track(_ webView: WKWebView, sessionID: String, prefix: String) {
        let trackID = "\(prefix)_\(sessionID.prefix(12))_\(UUID().uuidString.prefix(6))"
        inUseCount += 1
        totalCreated += 1
        peakActiveCount = max(peakActiveCount, inUseCount)
        trackedSessions[trackID] = TrackedWebView(id: trackID, createdAt: Date(), webView: webView)
        startStaleSessionReaperIfNeeded()
        logger.log("WebView acquired for \(sessionID)", category: .webView, level: .debug)
    }

    private func safeCleanupWebView(_ webView: WKWebView, wipeData: Bool) {
        webView.stopLoading()
        if wipeData {
            let dataStore = webView.configuration.websiteDataStore
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { }
            webView.configuration.userContentController.removeAllUserScripts()
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func reapStaleSessions() {
        let now = Date()
        for (key, tracked) in trackedSessions {
            if now.timeIntervalSince(tracked.createdAt) > staleSessionTimeoutSeconds {
                if let webView = tracked.webView {
                    safeCleanupWebView(webView, wipeData: true)
                }
                trackedSessions.removeValue(forKey: key)
                if inUseCount > 0 {
                    inUseCount -= 1
                }
                totalReleased += 1
            }
        }
    }

    private func reapDeallocatedSessions() {
        for (key, tracked) in trackedSessions where tracked.webView == nil {
            trackedSessions.removeValue(forKey: key)
            if inUseCount > 0 {
                inUseCount -= 1
            }
            totalReleased += 1
        }
    }

    private func startStaleSessionReaperIfNeeded() {
        guard staleSessionReaperTask == nil else { return }
        staleSessionReaperTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(90))
                guard !Task.isCancelled, let self else { return }
                self.reapStaleSessions()
                self.reapDeallocatedSessions()
                if self.trackedSessions.isEmpty && self.inUseCount == 0 {
                    self.staleSessionReaperTask = nil
                    return
                }
            }
        }
    }

    private func generateUserAgent() -> String {
        let osVersions = ["17_5_1", "17_6", "18_0", "18_1", "18_2", "18_3"]
        let osVersion = osVersions.randomElement() ?? "18_3"
        let majorMinor = osVersion.replacingOccurrences(of: "_", with: ".").components(separatedBy: ".").prefix(2).joined(separator: ".")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(majorMinor) Mobile/15E148 Safari/605.1.15"
    }
}
