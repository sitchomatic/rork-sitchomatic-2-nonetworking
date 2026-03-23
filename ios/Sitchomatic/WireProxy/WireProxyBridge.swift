import Foundation
import Network

@MainActor
final class WireProxyBridge {
    let localPort: Int
    private(set) var isConnected: Bool = false
    private(set) var bytesTransferred: Int64 = 0
    private var listener: NWListener?
    private let logger = DebugLogger.shared
    private var activeSessions: [String: NWConnection] = [:]

    init(localPort: Int = 0) {
        self.localPort = localPort == 0 ? Self.findAvailablePort() : localPort
    }

    func connect(config: WireGuardConfig) async throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: UInt16(localPort))!)
        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.logger.log("WireProxy bridge ready on port \(self?.localPort ?? 0)", category: .proxy, level: .info)
                case .failed(let error):
                    self?.isConnected = false
                    self?.logger.log("WireProxy bridge failed: \(error)", category: .proxy, level: .error)
                default:
                    break
                }
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }
        listener?.start(queue: .main)
    }

    func disconnect() {
        listener?.cancel()
        listener = nil
        isConnected = false
        for (_, conn) in activeSessions {
            conn.cancel()
        }
        activeSessions.removeAll()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let sessionID = UUID().uuidString.prefix(8).description
        activeSessions[sessionID] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.activeSessions.removeValue(forKey: sessionID)
                }
            }
        }
        connection.start(queue: .main)
    }

    private static func findAvailablePort() -> Int {
        Int.random(in: 10000...60000)
    }

    var diagnosticSummary: String {
        "Port: \(localPort) | Connected: \(isConnected) | Sessions: \(activeSessions.count) | Bytes: \(bytesTransferred)"
    }
}

nonisolated struct WireGuardConfig: Sendable {
    let privateKey: String
    let publicKey: String
    let endpoint: String
    let address: String
    let dns: String

    init(privateKey: String = "", publicKey: String = "", endpoint: String = "", address: String = "", dns: String = "1.1.1.1") {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.endpoint = endpoint
        self.address = address
        self.dns = dns
    }
}
