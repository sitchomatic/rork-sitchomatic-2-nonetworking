import WidgetKit
import SwiftUI

nonisolated struct WidgetSharedData: Codable, Sendable {
    var engineState: String
    var succeededCount: Int
    var failedCount: Int
    var noAccountCount: Int
    var permDisabledCount: Int
    var tempDisabledCount: Int
    var unsureCount: Int
    var errorCount: Int
    var totalSessions: Int
    var currentWave: Int
    var totalWaves: Int
    var overallProgress: Double
    var healthScore: Double
    var lastUpdated: Date

    static let defaultData = WidgetSharedData(
        engineState: "Idle",
        succeededCount: 0,
        failedCount: 0,
        noAccountCount: 0,
        permDisabledCount: 0,
        tempDisabledCount: 0,
        unsureCount: 0,
        errorCount: 0,
        totalSessions: 0,
        currentWave: 0,
        totalWaves: 0,
        overallProgress: 0,
        healthScore: 1.0,
        lastUpdated: Date()
    )
}

nonisolated struct SitchomaticEntry: TimelineEntry {
    let date: Date
    let data: WidgetSharedData
}

nonisolated struct SitchomaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> SitchomaticEntry {
        SitchomaticEntry(date: .now, data: .defaultData)
    }

    func getSnapshot(in context: Context, completion: @escaping (SitchomaticEntry) -> Void) {
        let data = loadSharedData()
        completion(SitchomaticEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SitchomaticEntry>) -> Void) {
        let data = loadSharedData()
        let entry = SitchomaticEntry(date: .now, data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadSharedData() -> WidgetSharedData {
        guard let defaults = UserDefaults(suiteName: "group.app.rork.sitchomatic"),
              let raw = defaults.data(forKey: "widgetSharedData"),
              let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw) else {
            return .defaultData
        }
        return decoded
    }
}

struct SmallWidgetView: View {
    let entry: SitchomaticEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: stateIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stateTint)
                Text(entry.data.engineState)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.primary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(entry.data.succeededCount)")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(.green)
                    Text("/")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("\(entry.data.totalSessions)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: entry.data.overallProgress)
                    .tint(.cyan)

                Text("Wave \(entry.data.currentWave)/\(max(entry.data.totalWaves, 1))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var stateIcon: String {
        switch entry.data.engineState {
        case "Running": "bolt.fill"
        case "Paused": "pause.fill"
        case "Completed": "checkmark.circle.fill"
        case "Failed": "xmark.circle.fill"
        default: "circle.dashed"
        }
    }

    private var stateTint: Color {
        switch entry.data.engineState {
        case "Running": .cyan
        case "Completed": .green
        case "Failed": .red
        case "Paused": .orange
        default: .secondary
        }
    }
}

struct MediumWidgetView: View {
    let entry: SitchomaticEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateTint)
                    Text(entry.data.engineState)
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(entry.data.succeededCount)")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.green)
                    Text("/ \(entry.data.totalSessions)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: entry.data.overallProgress)
                    .tint(.cyan)

                Text("Wave \(entry.data.currentWave)/\(max(entry.data.totalWaves, 1)) \u{2022} Health \(Int(entry.data.healthScore * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                categoryRow(icon: "checkmark.seal.fill", label: "Success", count: entry.data.succeededCount, color: .green)
                categoryRow(icon: "person.slash.fill", label: "No ACC", count: entry.data.noAccountCount, color: .indigo)
                categoryRow(icon: "lock.slash.fill", label: "Perm", count: entry.data.permDisabledCount, color: .red)
                categoryRow(icon: "clock.badge.exclamationmark.fill", label: "Temp", count: entry.data.tempDisabledCount, color: .orange)
                categoryRow(icon: "questionmark.diamond.fill", label: "Review", count: entry.data.unsureCount, color: .purple)
                categoryRow(icon: "exclamationmark.octagon.fill", label: "Error", count: entry.data.errorCount, color: .yellow)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private func categoryRow(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var stateIcon: String {
        switch entry.data.engineState {
        case "Running": "bolt.fill"
        case "Paused": "pause.fill"
        case "Completed": "checkmark.circle.fill"
        case "Failed": "xmark.circle.fill"
        default: "circle.dashed"
        }
    }

    private var stateTint: Color {
        switch entry.data.engineState {
        case "Running": .cyan
        case "Completed": .green
        case "Failed": .red
        case "Paused": .orange
        default: .secondary
        }
    }
}

struct CircularLockScreenView: View {
    let entry: SitchomaticEntry

    var body: some View {
        Gauge(value: entry.data.overallProgress) {
            Text("\(entry.data.succeededCount)")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct RectangularLockScreenView: View {
    let entry: SitchomaticEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption2)
                Text(entry.data.engineState)
                    .font(.caption2.weight(.bold))
            }

            HStack(spacing: 8) {
                Label("\(entry.data.succeededCount)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Label("\(entry.data.failedCount)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("W\(entry.data.currentWave)/\(max(entry.data.totalWaves, 1))")
            }
            .font(.caption2.weight(.semibold))

            ProgressView(value: entry.data.overallProgress)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct SitchomaticWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SitchomaticEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            CircularLockScreenView(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

struct SitchomaticWidget: Widget {
    let kind: String = "SitchomaticWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitchomaticProvider()) { entry in
            SitchomaticWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sitchomatic Status")
        .description("Live engine state, category breakdown, and wave progress.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
