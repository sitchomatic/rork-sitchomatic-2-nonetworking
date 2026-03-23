import Foundation

@Observable
final class DebugLogger {
    static let shared = DebugLogger()

    var entries: [LogEntry] = []
    private let maxEntries = 500

    func log(_ message: String, category: LogCategory = .general, level: LogLevel = .info) {
        let entry = LogEntry(message, category: category, level: level)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    func handleMemoryPressure() {
        if entries.count > 200 {
            entries = Array(entries.suffix(200))
        }
    }
}
