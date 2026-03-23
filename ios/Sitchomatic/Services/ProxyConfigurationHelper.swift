import Foundation
import WebKit

struct ProxyConfigurationHelper {

    static func configuredWebViewConfiguration(
        forSessionID sessionID: String
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }
}
