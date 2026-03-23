import Foundation

@Observable
@MainActor
final class RecordingSession {

    private(set) var actions: [RecordedAction] = []
    private(set) var isRecording: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var pickedLocator: String?
    private(set) var highlightedSelector: String?

    var mode: RecorderMode = .recording

    private var startTime: Date?
    private var pauseStartTime: Date?

    func startRecording() {
        actions.removeAll()
        isRecording = true
        isPaused = false
        startTime = Date()
        pauseStartTime = nil
        pickedLocator = nil
    }

    func pauseRecording() {
        isPaused = true
        pauseStartTime = Date()
    }

    func resumeRecording() {
        if let pauseStart = pauseStartTime {
            let pauseDuration = Int(Date().timeIntervalSince(pauseStart) * 1000)
            if pauseDuration >= 500 {
                let rounded = (pauseDuration / 100) * 100
                actions.append(RecordedAction(kind: .waitForTimeout, selector: nil, value: "\(rounded)", timestamp: Date()))
            }
        }
        isPaused = false
        pauseStartTime = nil
    }

    func stopRecording() {
        isRecording = false
        isPaused = false
        pauseStartTime = nil
    }

    func clearActions() {
        actions.removeAll()
        pickedLocator = nil
    }

    func removeLastAction() {
        guard !actions.isEmpty else { return }
        actions.removeLast()
    }

    func addAction(_ action: RecordedAction) {
        guard isRecording, !isPaused else { return }
        if action.kind == .navigation {
            if let last = actions.last, last.kind == .navigation,
               abs(last.timestamp.timeIntervalSince(action.timestamp)) < 1.0 { return }
        }
        if let last = actions.last, last.isDuplicate(of: action) { return }
        actions.append(action)
    }

    func addNavigationAction(url: String) {
        addAction(RecordedAction(kind: .navigation, selector: nil, value: url, timestamp: Date()))
    }

    func setPickedLocator(_ selector: String) { pickedLocator = selector }
    func setHighlightedSelector(_ selector: String?) { highlightedSelector = selector }

    var generatedCode: String {
        var lines: [String] = ["let page = try await orchestrator.newPage()", ""]
        for (index, action) in actions.enumerated() {
            lines.append(action.toSwiftCode())
            if action.kind == .navigation && index < actions.count - 1 {
                let next = actions[index + 1]
                if next.kind != .navigation && next.kind != .waitForTimeout {
                    lines.append("try await page.waitForLoadState(.networkIdle)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    var actionCount: Int { actions.count }
}

nonisolated enum RecorderMode: String, Sendable, CaseIterable {
    case recording, pickLocator, assertVisibility, assertText

    var displayName: String {
        switch self {
        case .recording: "Record"
        case .pickLocator: "Pick Locator"
        case .assertVisibility: "Assert Visible"
        case .assertText: "Assert Text"
        }
    }

    var iconName: String {
        switch self {
        case .recording: "record.circle"
        case .pickLocator: "target"
        case .assertVisibility: "eye"
        case .assertText: "text.quote"
        }
    }
}

nonisolated struct RecordedAction: Identifiable, Sendable, Codable {
    let id: UUID = UUID()
    let kind: ActionKind
    let selector: String?
    let value: String?
    let timestamp: Date

    func isDuplicate(of other: RecordedAction) -> Bool {
        kind == other.kind && selector == other.selector && value == other.value
            && abs(timestamp.timeIntervalSince(other.timestamp)) < 0.3
    }

    func toSwiftCode() -> String {
        switch kind {
        case .navigation: "try await page.goto(\"\(escapeSwift(value))\")"
        case .click: "try await page.locator(\"\(escapeSwift(selector))\").click()"
        case .fill: "try await page.locator(\"\(escapeSwift(selector))\").fill(\"\(escapeSwift(value))\")"
        case .check: "try await page.locator(\"\(escapeSwift(selector))\").check()"
        case .uncheck: "try await page.locator(\"\(escapeSwift(selector))\").uncheck()"
        case .select: "try await page.locator(\"\(escapeSwift(selector))\").selectOption(\"\(escapeSwift(value))\")"
        case .pressEnter: "try await page.locator(\"\(escapeSwift(selector))\").type(\"Enter\")"
        case .assertVisible: "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toBeVisible()"
        case .assertText: "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toContainText(\"\(escapeSwift(value))\")"
        case .assertValue: "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toHaveValue(\"\(escapeSwift(value))\")"
        case .waitForTimeout: "try await page.waitForTimeout(\(value ?? "1000"))"
        }
    }

    var displayDescription: String {
        switch kind {
        case .navigation: "goto(\"\(truncated(value))\")"
        case .click: "click(\"\(truncated(selector))\")"
        case .fill: "fill(\"\(truncated(selector))\", \"\(truncated(value))\")"
        case .check: "check(\"\(truncated(selector))\")"
        case .uncheck: "uncheck(\"\(truncated(selector))\")"
        case .select: "select(\"\(truncated(selector))\", \"\(truncated(value))\")"
        case .pressEnter: "press Enter on \"\(truncated(selector))\""
        case .assertVisible: "expect(\"\(truncated(selector))\").toBeVisible()"
        case .assertText: "expect(\"\(truncated(selector))\").toContainText(\"\(truncated(value))\")"
        case .assertValue: "expect(\"\(truncated(selector))\").toHaveValue(\"\(truncated(value))\")"
        case .waitForTimeout: "waitForTimeout(\(value ?? "1000")ms)"
        }
    }

    var iconName: String {
        switch kind {
        case .navigation: "globe"
        case .click: "cursorarrow.click"
        case .fill: "character.cursor.ibeam"
        case .check: "checkmark.square"
        case .uncheck: "square"
        case .select: "list.bullet"
        case .pressEnter: "return"
        case .assertVisible: "eye.fill"
        case .assertText: "text.magnifyingglass"
        case .assertValue: "equal.circle"
        case .waitForTimeout: "clock"
        }
    }

    private func truncated(_ str: String?) -> String {
        guard let str else { return "" }
        return str.count > 50 ? String(str.prefix(47)) + "..." : str
    }

    private func escapeSwift(_ str: String?) -> String {
        guard let str else { return "" }
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

nonisolated enum ActionKind: String, Sendable, Codable {
    case navigation, click, fill, check, uncheck, select, pressEnter
    case assertVisible, assertText, assertValue, waitForTimeout
}
