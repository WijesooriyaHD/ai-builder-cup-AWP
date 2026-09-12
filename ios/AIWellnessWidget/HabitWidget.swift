import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Shared Constants

private let kHabitAppGroup = "group.com.aiwellnesspal.app"

// MARK: - Timeline Entry

struct HabitRow: Identifiable {
    let id: String
    let text: String
    let emoji: String
    let checked: Bool
    var hasHabit: Bool { !text.isEmpty }
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let rows: [HabitRow]
    let completed: Int
    let total: Int
    let progress: Int // 0..100
    let hasHabits: Bool
}

// MARK: - Timeline Provider

struct HabitTimelineProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: kHabitAppGroup)

    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(
            date: Date(),
            rows: [
                HabitRow(id: "1", text: "Morning stretch", emoji: "🧘", checked: false),
                HabitRow(id: "2", text: "Drink water", emoji: "💧", checked: true),
                HabitRow(id: "3", text: "10-min walk", emoji: "🚶", checked: false),
            ],
            completed: 1, total: 3, progress: 33, hasHabits: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> HabitEntry {
        guard let d = sharedDefaults else { return emptyEntry() }
        let hasHabits = d.bool(forKey: "habit_has_habits")
        if !hasHabits {
            return emptyEntry()
        }
        let count = min(d.integer(forKey: "habit_count"), 4)
        var rows: [HabitRow] = []
        if count > 0 {
            for i in 1...count {
                let id = d.string(forKey: "habit_\(i)_id") ?? "\(i)"
                let text = d.string(forKey: "habit_\(i)_text") ?? ""
                let emoji = d.string(forKey: "habit_\(i)_emoji") ?? ""
                let checked = d.bool(forKey: "habit_\(i)_checked")
                if !text.isEmpty {
                    rows.append(HabitRow(id: id, text: text, emoji: emoji, checked: checked))
                }
            }
        }
        return HabitEntry(
            date: Date(),
            rows: rows,
            completed: d.integer(forKey: "habit_completed"),
            total: d.integer(forKey: "habit_total"),
            progress: d.integer(forKey: "habit_progress"),
            hasHabits: !rows.isEmpty
        )
    }

    private func emptyEntry() -> HabitEntry {
        HabitEntry(date: Date(), rows: [], completed: 0, total: 0, progress: 0, hasHabits: false)
    }
}

// MARK: - View

struct HabitWidgetEntryView: View {
    var entry: HabitEntry

    var body: some View {
        Group {
            if !entry.hasHabits {
                emptyView
            } else {
                contentView
            }
        }
        .widgetBackgroundGradient()
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("📋").font(.title)
            Text("No habits for today. Open the app to add some.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Text("📋").font(.title3)
                Text("Today's Habits")
                    .font(.headline)
                    .foregroundColor(Color("WidgetPrimary"))
                    .lineLimit(1)
            }

            ForEach(entry.rows) { row in
                habitRow(row)
            }

            Spacer(minLength: 0)

            // Progress
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.completed) of \(entry.total) done")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ProgressView(value: entry.total == 0 ? 0 : Double(entry.progress) / 100.0)
                    .tint(Color("WidgetPrimary"))
            }
        }
        .padding()
    }

    @ViewBuilder
    private func habitRow(_ row: HabitRow) -> some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: toggleIntent(for: row)) { rowContent(row) }
                .buttonStyle(.plain)
        } else {
            rowContent(row)
        }
        #else
        rowContent(row)
        #endif
    }

    private func rowContent(_ row: HabitRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.checked ? "checkmark.square.fill" : "square")
                .foregroundColor(Color("WidgetPrimary"))
                .font(.body)
            if !row.emoji.isEmpty {
                Text(row.emoji).font(.subheadline)
            }
            Text(row.text)
                .font(.subheadline)
                .strikethrough(row.checked, color: .secondary)
                .foregroundColor(row.checked ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func toggleIntent(for row: HabitRow) -> BackgroundIntent {
        // Matches AppState.backgroundCallback's `habit_toggle` handler:
        // aiwellnesspal://habit_toggle?id=..
        let encodedId = row.id.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? row.id
        let url = URL(string: "aiwellnesspal://habit_toggle?id=\(encodedId)")
        return BackgroundIntent(url: url, appGroup: kHabitAppGroup)
    }
    #endif
}

// MARK: - Widget Configuration

struct HabitWidget: Widget {
    let kind: String = "HabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitTimelineProvider()) { entry in
            HabitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Habits")
        .description("Check off today's habits from your home screen.")
        .supportedFamilies([.systemMedium])
    }
}
