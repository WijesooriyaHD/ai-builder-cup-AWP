import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Shared Constants

private let kIntentionAppGroup = "group.com.aiwellnesspal.app"

// MARK: - Timeline Entry

struct IntentionTaskRow {
    let text: String
    let id: String
    let checked: Bool
    var hasTask: Bool { !text.isEmpty }
}

struct IntentionEntry: TimelineEntry {
    let date: Date
    let intentionId: String
    let title: String
    let task1: IntentionTaskRow
    let task2: IntentionTaskRow
    let nextTask: String
    let allDone: Bool
    let hasIntention: Bool
    let completed: Int
    let total: Int
    let progress: Int // 0..100
}

// MARK: - Timeline Provider

struct IntentionTimelineProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: kIntentionAppGroup)

    func placeholder(in context: Context) -> IntentionEntry {
        IntentionEntry(
            date: Date(), intentionId: "1", title: "Sleep Better",
            task1: IntentionTaskRow(text: "No screens after 10pm", id: "t1", checked: false),
            task2: IntentionTaskRow(text: "Wind-down stretch", id: "t2", checked: false),
            nextTask: "Read 10 pages",
            allDone: false, hasIntention: true, completed: 2, total: 5, progress: 40)
    }

    func getSnapshot(in context: Context, completion: @escaping (IntentionEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IntentionEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> IntentionEntry {
        guard let d = sharedDefaults else { return emptyEntry() }
        let hasIntention = d.bool(forKey: "intention_has_intention")
        let intentionId = d.string(forKey: "intention_id") ?? ""
        if !hasIntention || intentionId.isEmpty {
            return emptyEntry()
        }
        return IntentionEntry(
            date: Date(),
            intentionId: intentionId,
            title: d.string(forKey: "intention_title") ?? "Wellness Intention",
            task1: IntentionTaskRow(
                text: d.string(forKey: "intention_task1_text") ?? "",
                id: d.string(forKey: "intention_task1_id") ?? "",
                checked: d.bool(forKey: "intention_task1_checked")),
            task2: IntentionTaskRow(
                text: d.string(forKey: "intention_task2_text") ?? "",
                id: d.string(forKey: "intention_task2_id") ?? "",
                checked: d.bool(forKey: "intention_task2_checked")),
            nextTask: d.string(forKey: "intention_next_task") ?? "",
            allDone: d.bool(forKey: "intention_all_done"),
            hasIntention: true,
            completed: d.integer(forKey: "intention_completed"),
            total: d.integer(forKey: "intention_total"),
            progress: d.integer(forKey: "intention_progress")
        )
    }

    private func emptyEntry() -> IntentionEntry {
        IntentionEntry(
            date: Date(), intentionId: "", title: "Wellness Intention",
            task1: IntentionTaskRow(text: "", id: "", checked: false),
            task2: IntentionTaskRow(text: "", id: "", checked: false),
            nextTask: "", allDone: false,
            hasIntention: false, completed: 0, total: 0, progress: 0)
    }
}

// MARK: - View

struct IntentionWidgetEntryView: View {
    var entry: IntentionEntry

    var body: some View {
        Group {
            if !entry.hasIntention {
                emptyView
            } else {
                contentView
            }
        }
        .overlay(alignment: .topTrailing) {
            WidgetThemeToggleButton(isDark: widgetThemeIsDark())
                .padding(10)
        }
        .widgetBackgroundImage("bg_wellness_intention")
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            WidgetChip {
                VStack(spacing: 6) {
                    Text("🎯").font(.title2)
                    Text("Open the app and pin an intention to see it here.")
                        .font(.footnote)
                        .foregroundColor(widgetTextColor())
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: icon + title (no chip)
            HStack(spacing: 8) {
                Text("🎯").font(.subheadline)
                Text(entry.title)
                    .font(.subheadline).bold()
                    .foregroundColor(Color("WidgetPrimary"))
                    .lineLimit(1)
            }

            if entry.allDone {
                WidgetChip {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .foregroundColor(Color("WidgetPrimary"))
                        Text("All steps complete 🎉")
                            .font(.subheadline)
                            .foregroundColor(widgetSecondaryTextColor())
                            .lineLimit(1)
                    }
                }
            } else {
                if entry.task1.hasTask { taskRow(entry.task1) }
                if entry.task2.hasTask { taskRow(entry.task2) }
            }

            Spacer(minLength: 0)

            // Progress (no chip)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.completed) of \(entry.total) steps")
                    .font(.caption2)
                    .foregroundColor(Color("WidgetPrimary"))
                ProgressView(value: entry.total == 0 ? 0 : Double(entry.progress) / 100.0)
                    .tint(Color("WidgetPrimary"))
            }
        }
        .padding()
    }

    @ViewBuilder
    private func taskRow(_ task: IntentionTaskRow) -> some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: toggleIntent(for: task)) { WidgetChip { taskRowContent(task) } }
                .buttonStyle(.plain)
        } else {
            WidgetChip { taskRowContent(task) }
        }
        #else
        WidgetChip { taskRowContent(task) }
        #endif
    }

    private func taskRowContent(_ task: IntentionTaskRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: task.checked ? "checkmark.square.fill" : "square")
                .foregroundColor(Color("WidgetPrimary"))
                .font(.body)
            Text(task.text)
                .font(.subheadline)
                .strikethrough(task.checked, color: widgetSecondaryTextColor())
                .foregroundColor(task.checked ? widgetSecondaryTextColor() : widgetTextColor())
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func toggleIntent(for task: IntentionTaskRow) -> BackgroundIntent {
        let encodedId = entry.intentionId.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? entry.intentionId
        let encodedTask = task.id.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? task.id
        let url = URL(
            string: "aiwellnesspal://intention_toggle?id=\(encodedId)&task=\(encodedTask)")
        return BackgroundIntent(url: url, appGroup: kIntentionAppGroup)
    }
    #endif
}

// MARK: - Widget Configuration

struct IntentionWidget: Widget {
    let kind: String = "IntentionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntentionTimelineProvider()) { entry in
            IntentionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wellness Intention")
        .description("Your current wellness intention tasks and progress.")
        .supportedFamilies([.systemMedium])
    }
}
