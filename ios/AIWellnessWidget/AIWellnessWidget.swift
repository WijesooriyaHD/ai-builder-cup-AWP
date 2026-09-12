import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Shared Constants

private let kAppGroup = "group.com.aiwellnesspal.app"

// MARK: - Shared widget background

/// A soft diagonal gradient used as the background for every home-screen
/// widget in this extension — decent and eye-catching without hurting text
/// contrast. Mirrors the Android `widget_background_gradient` drawable.
let kWidgetBackgroundGradient = LinearGradient(
    colors: [
        Color(red: 0.89, green: 0.93, blue: 0.98), // #E3EEFB light primary tint
        Color(red: 0.95, green: 0.97, blue: 0.996), // #F3F7FE
        Color.white,
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

extension View {
    /// Applies the shared widget gradient as the WidgetKit container background
    /// (required on iOS 17+); falls back to a plain background on older iOS.
    @ViewBuilder
    func widgetBackgroundGradient() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { kWidgetBackgroundGradient }
        } else {
            background(kWidgetBackgroundGradient)
        }
    }

    /// Applies a full-bleed light/dark background image as the WidgetKit
    /// container background. [baseName] is the asset base (e.g. "bg_todays_plan");
    /// the "_light"/"_dark" variant is chosen from [scheme].
    @ViewBuilder
    func widgetBackgroundImage(_ baseName: String, scheme: ColorScheme) -> some View {
        let asset = "\(baseName)_\(scheme == .dark ? "dark" : "light")"
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) {
                GeometryReader { geo in
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        } else {
            background(
                Image(asset).resizable().scaledToFill()
            )
        }
    }
}

/// A rounded white "chip" wrapper so widget text stays readable over the
/// background image. Mirrors the Android `widget_chip` drawable.
struct WidgetChip<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.95))
            )
    }
}

// MARK: - Timeline Entry

struct WellnessTaskRow {
    let text: String
    let id: String
    let checked: Bool
    var hasTask: Bool { !text.isEmpty }
}

struct WellnessEntry: TimelineEntry {
    let date: Date
    let planId: String
    let focus: String
    let task1: WellnessTaskRow
    let task2: WellnessTaskRow
    let nextTask: String
    let allDone: Bool
    let completed: Int
    let total: Int
    let progress: Int // 0..100
    let isPlaceholder: Bool
}

// MARK: - Timeline Provider

struct WellnessTimelineProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: kAppGroup)

    func placeholder(in context: Context) -> WellnessEntry {
        WellnessEntry(
            date: Date(),
            planId: "",
            focus: "Today's Focus",
            task1: WellnessTaskRow(text: "Morning Stretch", id: "1", checked: false),
            task2: WellnessTaskRow(text: "Breathwork", id: "2", checked: false),
            nextTask: "Hydrate",
            allDone: false, completed: 1, total: 4, progress: 25,
            isPlaceholder: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WellnessEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WellnessEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes (matches the Dart-side 30-min cap).
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadEntry() -> WellnessEntry {
        guard let defaults = sharedDefaults else {
            return placeholderEntry()
        }

        let isPlaceholder = defaults.bool(forKey: "wellness_placeholder")
        if isPlaceholder {
            return placeholderEntry()
        }

        let planId = defaults.string(forKey: "wellness_plan_id") ?? ""
        let focus = defaults.string(forKey: "wellness_focus") ?? "Today's Focus"

        return WellnessEntry(
            date: Date(),
            planId: planId,
            focus: focus,
            task1: WellnessTaskRow(
                text: defaults.string(forKey: "wellness_task1_text") ?? "",
                id: defaults.string(forKey: "wellness_task1_id") ?? "",
                checked: defaults.bool(forKey: "wellness_task1_checked")),
            task2: WellnessTaskRow(
                text: defaults.string(forKey: "wellness_task2_text") ?? "",
                id: defaults.string(forKey: "wellness_task2_id") ?? "",
                checked: defaults.bool(forKey: "wellness_task2_checked")),
            nextTask: defaults.string(forKey: "wellness_next_task") ?? "",
            allDone: defaults.bool(forKey: "wellness_all_done"),
            completed: defaults.integer(forKey: "wellness_completed"),
            total: defaults.integer(forKey: "wellness_total"),
            progress: defaults.integer(forKey: "wellness_progress"),
            isPlaceholder: false
        )
    }

    private func placeholderEntry() -> WellnessEntry {
        WellnessEntry(
            date: Date(),
            planId: "",
            focus: "",
            task1: WellnessTaskRow(text: "", id: "", checked: false),
            task2: WellnessTaskRow(text: "", id: "", checked: false),
            nextTask: "", allDone: false, completed: 0, total: 0, progress: 0,
            isPlaceholder: true
        )
    }
}

// MARK: - Widget View

struct AIWellnessWidgetEntryView: View {
    var entry: WellnessEntry

    @Environment(\.widgetFamily) var family

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if entry.isPlaceholder {
                placeholderView
            } else {
                contentView
            }
        }
        .widgetBackgroundImage("bg_todays_plan", scheme: scheme)
    }

    private var placeholderView: some View {
        VStack {
            Spacer()
            WidgetChip {
                Text("Open the app to start your wellness day.")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: icon + focus (no chip)
            HStack(spacing: 8) {
                Text("✨").font(.subheadline)
                Text(entry.focus)
                    .font(.subheadline).bold()
                    .foregroundColor(Color("WidgetPrimary"))
                    .lineLimit(1)
            }

            if entry.allDone {
                WidgetChip {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .foregroundColor(Color("WidgetPrimary"))
                        Text("All actions complete 🎉")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                Text("\(entry.completed) of \(entry.total) actions")
                    .font(.caption2)
                    .foregroundColor(Color("WidgetPrimary"))
                ProgressView(value: entry.total == 0 ? 0 : Double(entry.progress) / 100.0)
                    .tint(Color("WidgetPrimary"))
            }
        }
        .padding()
    }

    @ViewBuilder
    private func taskRow(_ task: WellnessTaskRow) -> some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: toggleIntent(for: task)) {
                WidgetChip { rowContent(task) }
            }
            .buttonStyle(.plain)
        } else {
            WidgetChip { rowContent(task) }
        }
        #else
        WidgetChip { rowContent(task) }
        #endif
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func toggleIntent(for task: WellnessTaskRow) -> BackgroundIntent {
        // Matches AppState.backgroundCallback's `wellness_toggle` handler:
        // aiwellnesspal://wellness_toggle?plan_id=..&action_id=..
        let encodedPlan = entry.planId.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? entry.planId
        let encodedAction = task.id.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? task.id
        let url = URL(
            string: "aiwellnesspal://wellness_toggle?plan_id=\(encodedPlan)&action_id=\(encodedAction)")
        return BackgroundIntent(url: url, appGroup: kAppGroup)
    }
    #endif

    private func rowContent(_ task: WellnessTaskRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: task.checked ? "checkmark.square.fill" : "square")
                .foregroundColor(Color("WidgetPrimary"))
                .font(.body)
            Text(task.text)
                .font(.subheadline)
                .strikethrough(task.checked, color: .secondary)
                .foregroundColor(task.checked ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Widget Configuration

struct AIWellnessWidget: Widget {
    let kind: String = "AIWellnessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WellnessTimelineProvider()) { entry in
            AIWellnessWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Plan")
        .description("Your daily wellness plan at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle (hosts every widget in this extension)

@main
struct AIWellnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIWellnessWidget()
        IntentionWidget()
        HabitWidget()
    }
}
