import Foundation
import Network
import WebKit

struct ProxyConfigurationHelper {

    static func createProxyConfiguration(host: String, port: Int) -> ProxyConfiguration? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let nwHost = NWEndpoint.Host(host)
        let config = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: nwHost, port: nwPort))
        return config
    }

    static func configuredWebViewConfiguration(
        forSessionID sessionID: String,
        networkManager: SimpleNetworkManager
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        if let endpoint = networkManager.proxyEndpoint(forSessionID: sessionID) {
            if let proxyConfig = createProxyConfiguration(host: endpoint.host, port: endpoint.port) {
                config.websiteDataStore.proxyConfigurations = [proxyConfig]
            }
        }

        return config
    }
}
