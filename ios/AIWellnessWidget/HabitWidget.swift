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
    let allDone: Bool
}

// MARK: - Timeline Provider

struct HabitTimelineProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: kHabitAppGroup)

    func placeholder(in context: Context) -> HabitEntry {
        // Only two rows are ever shown, matching the placed widget.
        HabitEntry(
            date: Date(),
            rows: [
                HabitRow(id: "1", text: "Morning stretch", emoji: "🧘", checked: false),
                HabitRow(id: "2", text: "Drink water", emoji: "💧", checked: false),
            ],
            completed: 1, total: 3, progress: 33, hasHabits: true, allDone: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        // Now + next midnight, so ticks clear and the new day's habits show on time.
        let entries = WidgetDay.timelineDates().map { loadEntry(at: $0) }
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func loadEntry(at date: Date = Date()) -> HabitEntry {
        guard let d = WidgetDay.habits(at: date) else { return emptyEntry(date) }
        let hasHabits = d.bool(forKey: "habit_has_habits")
        if !hasHabits {
            return emptyEntry(date)
        }
        // Read exactly two fixed slots, mirroring the Wellness Intention
        // widget. This never depends on `habit_count`, so a stale/old value
        // can never cause more than two rows to render.
        var rows: [HabitRow] = []
        for i in 1...2 {
            let text = d.string(forKey: "habit_\(i)_text") ?? ""
            if text.isEmpty { continue }
            let id = d.string(forKey: "habit_\(i)_id") ?? "\(i)"
            let emoji = d.string(forKey: "habit_\(i)_emoji") ?? ""
            let checked = d.bool(forKey: "habit_\(i)_checked")
            rows.append(HabitRow(id: id, text: text, emoji: emoji, checked: checked))
        }
        let total = d.integer(forKey: "habit_total")
        let completed = d.integer(forKey: "habit_completed")
        let allDone = d.bool(forKey: "habit_all_done")
        return HabitEntry(
            date: date,
            rows: rows,
            completed: completed,
            total: total,
            progress: d.integer(forKey: "habit_progress"),
            hasHabits: total > 0,
            allDone: allDone
        )
    }

    private func emptyEntry(_ date: Date = Date()) -> HabitEntry {
        HabitEntry(
            date: date, rows: [], completed: 0, total: 0, progress: 0,
            hasHabits: false, allDone: false)
    }
}

// MARK: - View

struct HabitWidgetEntryView: View {
    var entry: HabitEntry

    /// Per-widget theme id (independent light/dark).
    private let wid = "habit"

    var body: some View {
        Group {
            if !entry.hasHabits {
                emptyView
            } else {
                contentView
            }
        }
        .overlay(alignment: .topTrailing) {
            WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid)
                .padding(10)
        }
        .widgetBackgroundImage("bg_todays_habits", widgetId: wid)
        // Tapping anywhere outside the interactive buttons opens the app on the
        // Habit Builder tab. The `homeWidget` query item is REQUIRED: the
        // home_widget plugin only recognizes a launch URL as a widget URL when
        // it contains a query item named `homeWidget` (isWidgetUrl), otherwise
        // the URL is dropped and the app just opens to its default screen.
        .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=habit_builder"))
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            WidgetChip(wid) {
                VStack(spacing: 6) {
                    Text("📋").font(.title2)
                    Text("No habits for today. Open the app to add some.")
                        .font(.footnote)
                        .foregroundColor(widgetTextColor(wid))
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header (no chip)
            HStack(spacing: 8) {
                Text("📋").font(.subheadline)
                Text("Today's Habits")
                    .font(.subheadline).bold()
                    .foregroundColor(Color("WidgetPrimary"))
                    .lineLimit(1)
            }

            if entry.allDone {
                WidgetChip(wid) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .foregroundColor(Color("WidgetPrimary"))
                        Text("All habits done 🎉")
                            .font(.subheadline)
                            .foregroundColor(widgetSecondaryTextColor(wid))
                            .lineLimit(1)
                    }
                }
            } else {
                // Show the first two incomplete habits, matching the
                // Wellness Intention widget.
                ForEach(Array(entry.rows.prefix(2))) { row in
                    habitRow(row)
                }
            }

            Spacer(minLength: 0)

            // Progress (no chip)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.completed) of \(entry.total) done")
                    .font(.caption2)
                    .foregroundColor(Color("WidgetPrimary"))
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
            Button(intent: toggleIntent(for: row)) { WidgetChip(wid) { rowContent(row) } }
                .buttonStyle(.plain)
        } else {
            WidgetChip(wid) { rowContent(row) }
        }
        #else
        WidgetChip(wid) { rowContent(row) }
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
                .strikethrough(row.checked, color: widgetSecondaryTextColor(wid))
                .foregroundColor(row.checked ? widgetSecondaryTextColor(wid) : widgetTextColor(wid))
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
