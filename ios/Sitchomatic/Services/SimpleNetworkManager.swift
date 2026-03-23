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

@Observable
@MainActor
final class SimpleNetworkManager {
    static let shared = SimpleNetworkManager()

    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var statusMessage: String = "Not connected"
    private let logger = DebugLogger.shared
    private(set) var lastLatencyMs: Int = 0
    private(set) var totalBytesIn: Int64 = 0
    private(set) var totalBytesOut: Int64 = 0
    private(set) var isAutoReconnecting: Bool = false
    private(set) var reconnectAttempts: Int = 0
    private let maxAutoReconnectAttempts: Int = 5

    var quickStatusLine: String {
        let latencyStr = lastLatencyMs > 0 ? " | Latency: \(lastLatencyMs)ms" : ""
        return "\(connectionStatus.displayName) | NordVPN (External)\(latencyStr)"
    }

    var bandwidthSummary: String {
        let inMB = Double(totalBytesIn) / 1_048_576
        let outMB = Double(totalBytesOut) / 1_048_576
        return String(format: "In: %.2f MB | Out: %.2f MB", inMB, outMB)
    }

    private init() {}

    func connect() async {
        connectionStatus = .connecting
        statusMessage = "Connecting..."
        connectionStatus = .connected
        statusMessage = "Connected (NordVPN external)"
    }

    func disconnect() {
        connectionStatus = .disconnected
        statusMessage = "Disconnected"
        isAutoReconnecting = false
        reconnectAttempts = 0
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
}
