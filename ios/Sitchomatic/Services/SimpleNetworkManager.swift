import Foundation
import WebKit

nonisolated enum ConnectionStatus: String, Sendable {
    case connected
    case connecting
    case disconnected
    case error

    var displayName: String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }

    var iconName: String {
        switch self {
        case .connected: "wifi"
        case .connecting: "wifi.exclamationmark"
        case .disconnected: "wifi.slash"
        case .error: "exclamationmark.triangle"
        }
    }
}

nonisolated struct ProxyEndpoint: Sendable {
    let host: String
    let port: Int
}

nonisolated enum ActiveNetworkConfig: Sendable {
    case direct
    case socks5(host: String, port: Int)

    var label: String {
        switch self {
        case .direct: "Direct"
        case .socks5(let host, let port): "SOCKS5(\(host):\(port))"
        }
    }
}

@Observable
@MainActor
final class SimpleNetworkManager {
    static let shared = SimpleNetworkManager()

    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var statusMessage: String = "Not connected"
    private(set) var proxyCount: Int = 0
    private(set) var currentNetworkConfig: ActiveNetworkConfig = .direct

    private var proxyEndpoints: [String: ProxyEndpoint] = [:]
    private var wireProxyBridges: [WireProxyBridge] = []
    private let logger = DebugLogger.shared
    private var socks5Proxies: [(host: String, port: Int)] = []
    private var currentIndex: Int = 0
    private var rotationTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var bandwidthTask: Task<Void, Never>?
    private(set) var lastLatencyMs: Int = 0
    private(set) var totalBytesIn: Int64 = 0
    private(set) var totalBytesOut: Int64 = 0
    private(set) var proxyHealthStatus: [String: ProxyHealth] = [:]
    private(set) var isAutoReconnecting: Bool = false
    private(set) var reconnectAttempts: Int = 0
    private let maxAutoReconnectAttempts: Int = 5

    var quickStatusLine: String {
        let latencyStr = lastLatencyMs > 0 ? " | Latency: \(lastLatencyMs)ms" : ""
        return "\(connectionStatus.displayName) | Proxies: \(proxyCount) | Config: \(currentNetworkConfig.label)\(latencyStr)"
    }

    var bandwidthSummary: String {
        let inMB = Double(totalBytesIn) / 1_048_576
        let outMB = Double(totalBytesOut) / 1_048_576
        return String(format: "In: %.2f MB | Out: %.2f MB", inMB, outMB)
    }

    var healthyProxyCount: Int {
        proxyHealthStatus.values.filter { $0 == .healthy }.count
    }

    private init() {}

    func connect() async {
        connectionStatus = .connecting
        statusMessage = "Connecting..."

        if !socks5Proxies.isEmpty {
            do {
                try await connectSOCKS5()
                connectionStatus = .connected
                statusMessage = "Connected via SOCKS5"
            } catch {
                connectionStatus = .error
                statusMessage = "Connection failed: \(error.localizedDescription)"
            }
        } else {
            connectionStatus = .connected
            statusMessage = "Connected (direct)"
            currentNetworkConfig = .direct
        }
    }

    func disconnect() {
        for bridge in wireProxyBridges {
            bridge.disconnect()
        }
        wireProxyBridges.removeAll()
        proxyEndpoints.removeAll()
        proxyCount = 0
        connectionStatus = .disconnected
        statusMessage = "Disconnected"
        currentNetworkConfig = .direct
        rotationTask?.cancel()
        rotationTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        bandwidthTask?.cancel()
        bandwidthTask = nil
        proxyHealthStatus.removeAll()
        isAutoReconnecting = false
        reconnectAttempts = 0
    }

    func proxyEndpoint(forSessionID sessionID: String) -> ProxyEndpoint? {
        if let cached = proxyEndpoints[sessionID] {
            return cached
        }

        guard !wireProxyBridges.isEmpty else { return nil }

        let bridge = wireProxyBridges[abs(sessionID.hashValue) % wireProxyBridges.count]
        let endpoint = ProxyEndpoint(host: "127.0.0.1", port: bridge.localPort)
        proxyEndpoints[sessionID] = endpoint
        return endpoint
    }

    func networkConfiguration(forSessionID sessionID: String) -> ActiveNetworkConfig {
        if let endpoint = proxyEndpoint(forSessionID: sessionID) {
            return .socks5(host: endpoint.host, port: endpoint.port)
        }
        return currentNetworkConfig
    }

    func clearProxyEndpoint(forSessionID sessionID: String) {
        proxyEndpoints.removeValue(forKey: sessionID)
    }

    func configureSOCKS5Proxies(_ proxies: [(host: String, port: Int)]) {
        socks5Proxies = proxies
        logger.log("Configured \(proxies.count) SOCKS5 proxies", category: .network, level: .info)
    }

    func addWireProxyBridge(_ bridge: WireProxyBridge) {
        wireProxyBridges.append(bridge)
        proxyCount = wireProxyBridges.count
        logger.log("Added WireProxy bridge (total: \(proxyCount))", category: .network, level: .info)
    }

    func rotateToNextProxy() async {
        guard !wireProxyBridges.isEmpty else { return }
        currentIndex = (currentIndex + 1) % wireProxyBridges.count
        proxyEndpoints.removeAll()
        logger.log("Rotated to proxy index \(currentIndex)", category: .network, level: .debug)
    }

    func measureLatency() async {
        let start = Date()
        let url = URL(string: "https://1.1.1.1/dns-query")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(start)
            lastLatencyMs = Int(elapsed * 1000)
            logger.log("Latency measured: \(lastLatencyMs)ms", category: .network, level: .debug)
        } catch {
            lastLatencyMs = -1
            logger.log("Latency measurement failed: \(error.localizedDescription)", category: .network, level: .warning)
        }
    }

    func runProxyHealthChecks() async {
        for (index, bridge) in wireProxyBridges.enumerated() {
            let key = "bridge_\(index)_\(bridge.localPort)"
            if bridge.isConnected {
                proxyHealthStatus[key] = .healthy
            } else {
                proxyHealthStatus[key] = .unreachable
            }
        }
        logger.log("Health check: \(healthyProxyCount)/\(wireProxyBridges.count) healthy", category: .network, level: .info)
    }

    func startPeriodicHealthChecks(intervalSeconds: Int) {
        healthCheckTask?.cancel()
        guard intervalSeconds > 0 else { return }
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled, let self else { return }
                await self.runProxyHealthChecks()
            }
        }
    }

    func startProxyRotation(intervalSeconds: Int) {
        rotationTask?.cancel()
        guard intervalSeconds > 0 else { return }
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled, let self else { return }
                await self.rotateToNextProxy()
            }
        }
    }

    func attemptAutoReconnect() async {
        guard !isAutoReconnecting else { return }
        isAutoReconnecting = true
        reconnectAttempts = 0
        let maxAttempts = AutomationSettings.shared.maxNetworkRetries

        while reconnectAttempts < maxAttempts && connectionStatus != .connected {
            reconnectAttempts += 1
            logger.log("Auto-reconnect attempt \(reconnectAttempts)/\(maxAttempts)", category: .network, level: .info)
            await connect()
            if connectionStatus == .connected { break }
            let delay = min(Double(reconnectAttempts) * 2.0, 15.0)
            try? await Task.sleep(for: .seconds(delay))
        }

        isAutoReconnecting = false
        if connectionStatus != .connected {
            logger.log("Auto-reconnect exhausted after \(reconnectAttempts) attempts", category: .network, level: .error)
        }
    }

    func resetBandwidthCounters() {
        totalBytesIn = 0
        totalBytesOut = 0
    }

    private func connectSOCKS5() async throws {
        guard let first = socks5Proxies.first else { return }
        currentNetworkConfig = .socks5(host: first.host, port: first.port)
        proxyCount = socks5Proxies.count
    }
}

nonisolated enum ProxyHealth: String, Sendable {
    case healthy
    case degraded
    case unreachable

    var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .unreachable: "Unreachable"
        }
    }

    var iconName: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .unreachable: "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .healthy: "green"
        case .degraded: "orange"
        case .unreachable: "red"
        }
    }
}
