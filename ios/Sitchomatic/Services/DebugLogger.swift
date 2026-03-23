import Foundation
import os

@Observable
@MainActor
final class DebugLogger {
    static let shared = DebugLogger()

    nonisolated enum LogLevel: Int, Sendable, Comparable, CaseIterable {
        case trace = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case critical = 5

        nonisolated static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var prefix: String {
            switch self {
            case .trace: "🔍"
            case .debug: "🐛"
            case .info: "ℹ️"
            case .warning: "⚠️"
            case .error: "❌"
            case .critical: "🔴"
            }
        }

        var title: String {
            switch self {
            case .trace: "Trace"
            case .debug: "Debug"
            case .info: "Info"
            case .warning: "Warn"
            case .error: "Error"
            case .critical: "Critical"
            }
        }
    }

    nonisolated enum LogCategory: String, Sendable, CaseIterable {
        case automation
        case webView
        case network
        case proxy
        case stealth
        case persistence
        case crash
        case ui
        case ppsr
        case general

        var title: String {
            switch self {
            case .automation: "Automation"
            case .webView: "WebView"
            case .network: "Network"
            case .proxy: "Proxy"
            case .stealth: "Stealth"
            case .persistence: "Storage"
            case .crash: "Crash"
            case .ui: "UI"
            case .ppsr: "PPSR"
            case .general: "General"
            }
        }
    }

    nonisolated struct LogEntry: Identifiable, Sendable {
        let id: UUID = UUID()
        let timestamp: Date
        let category: LogCategory
        let level: LogLevel
        let message: String

        var formatted: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return "\(level.prefix) [\(formatter.string(from: timestamp))] [\(category.rawValue)] \(message)"
        }
    }

    private(set) var entries: [LogEntry] = []
    var minimumLevel: LogLevel = .debug
    private let maxEntries: Int = 5000
    private let osLog = Logger(subsystem: "com.sitchomatic.v16", category: "main")

    private init() {}

    func log(_ message: String, category: LogCategory = .general, level: LogLevel = .debug) {
        guard level >= minimumLevel else { return }

        let entry = LogEntry(
            timestamp: Date(),
            category: category,
            level: level,
            message: message
        )
        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        switch level {
        case .trace, .debug:
            osLog.debug("\(message)")
        case .info:
            osLog.info("\(message)")
        case .warning:
            osLog.warning("\(message)")
        case .error:
            osLog.error("\(message)")
        case .critical:
            osLog.critical("\(message)")
        }
    }

    func clear() {
        entries.removeAll()
    }

    func entries(for category: LogCategory) -> [LogEntry] {
        entries.filter { $0.category == category }
    }

    func entries(minLevel: LogLevel) -> [LogEntry] {
        entries.filter { $0.level >= minLevel }
    }

    var recentErrors: [LogEntry] {
        Array(entries.filter { $0.level >= .error }.suffix(50).reversed())
    }

    func exportLog() -> String {
        entries.map { $0.formatted }.joined(separator: "\n")
    }
}
