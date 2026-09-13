import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Shared Constants

private let kAppGroup = "group.com.aiwellnesspal.app"

// MARK: - Manual widget theme (light/dark toggle)

/// The app group all widgets share. Kept internal (not private) so the theme
/// helpers below are usable from every widget file in this extension.
let kWidgetAppGroup = "group.com.aiwellnesspal.app"

/// Whether the widgets should render in their dark theme. This is driven by a
/// manual in-widget toggle (see `WidgetThemeToggleButton`) rather than the
/// system appearance, because WidgetKit does not reliably re-render a placed
/// widget's cached image rendition when the system light/dark mode changes.
/// The value is stored in the shared app group under `widget_theme_dark` and
/// flipped from Dart's `backgroundCallback` (`widget_theme_toggle`).
func widgetThemeIsDark() -> Bool {
    UserDefaults(suiteName: kWidgetAppGroup)?.bool(forKey: "widget_theme_dark") ?? false
}

/// Primary text color that follows the manual widget theme (dark text on the
/// light chip, light text on the dark chip). Using a fixed color per theme —
/// rather than `.primary` — keeps text readable even when the manual theme
/// differs from the system appearance.
func widgetTextColor() -> Color {
    widgetThemeIsDark() ? Color.white : Color(red: 0.11, green: 0.12, blue: 0.15)
}

/// Secondary/dimmed text color for the current manual widget theme.
func widgetSecondaryTextColor() -> Color {
    widgetThemeIsDark()
        ? Color.white.opacity(0.75)
        : Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.6)
}

/// A small sun/moon button, placed in the top-right of each widget, that flips
/// the manual light/dark theme. Tapping fires the shared `BackgroundIntent`
/// with the `widget_theme_toggle` URL, which Dart handles by flipping
/// `widget_theme_dark` and re-pushing the widgets.
struct WidgetThemeToggleButton: View {
    var isDark: Bool

    var body: some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: themeToggleIntent()) { iconLabel }
                .buttonStyle(.plain)
        } else {
            iconLabel
        }
        #else
        iconLabel
        #endif
    }

    private var iconLabel: some View {
        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isDark ? .yellow : .orange)
            .padding(6)
            .background(
                Circle().fill(
                    isDark
                        ? Color(red: 0.118, green: 0.145, blue: 0.180).opacity(0.65)
                        : Color.white.opacity(0.9)
                )
            )
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func themeToggleIntent() -> BackgroundIntent {
        let url = URL(string: "aiwellnesspal://widget_theme_toggle")
        return BackgroundIntent(url: url, appGroup: kWidgetAppGroup)
    }
    #endif
}

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
    /// container background. [baseName] is the asset base (e.g. "bg_todays_plan").
    ///
    /// The concrete "_light"/"_dark" variant is chosen from the SwiftUI color
    /// scheme *inside the view body*, not from an asset-catalog appearance
    /// variant. WidgetKit re-evaluates the view body when the system appearance
    /// changes, but it does NOT re-resolve the rendition baked into a cached
    /// `Image` snapshot — so selecting by `colorScheme` here is what makes the
    /// background reliably switch both light→dark and back.
    @ViewBuilder
    func widgetBackgroundImage(_ baseName: String) -> some View {
        modifier(WidgetBackgroundImageModifier(baseName: baseName))
    }
}

/// Picks the light/dark background image from the manual widget theme stored in
/// the app group (see `widgetThemeIsDark()`), not the system appearance.
private struct WidgetBackgroundImageModifier: ViewModifier {
    let baseName: String

    private var asset: String { "\(baseName)_\(widgetThemeIsDark() ? "dark" : "light")" }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                GeometryReader { geo in
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        } else {
            content.background(
                Image(asset).resizable().scaledToFill()
            )
        }
    }
}

/// A rounded "chip" wrapper so widget text stays readable over the background
/// image. The fill adapts to the system appearance (near-white in light mode,
/// dark translucent in dark mode) via the `WidgetChipBackground` color asset,
/// so text painted with `WidgetPrimary` / `.primary` stays legible in both.
/// Mirrors the Android `widget_chip` drawable.
struct WidgetChip<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    /// Chosen from the manual widget theme (app group), so it flips together
    /// with the background image: near-white in light, dark translucent in dark.
    private var fill: Color {
        widgetThemeIsDark()
            ? Color(red: 0.118, green: 0.145, blue: 0.180).opacity(0.60)
            : Color.white.opacity(0.95)
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
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

    var body: some View {
        Group {
            if entry.isPlaceholder {
                placeholderView
            } else {
                contentView
            }
        }
        .overlay(alignment: .topTrailing) {
            WidgetThemeToggleButton(isDark: widgetThemeIsDark())
                .padding(10)
        }
        .widgetBackgroundImage("bg_todays_plan")
        // Tapping anywhere outside the interactive buttons opens the app on the
        // Home (daily plan) tab. `homeWidget` query item required (see
        // HabitWidget for the rationale).
        .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=home"))
    }

    private var placeholderView: some View {
        VStack {
            Spacer()
            WidgetChip {
                Text("Open the app to start your wellness day.")
                    .font(.subheadline)
                    .foregroundColor(widgetTextColor())
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
                .strikethrough(task.checked, color: widgetSecondaryTextColor())
                .foregroundColor(task.checked ? widgetSecondaryTextColor() : widgetTextColor())
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
    @WidgetBundleBuilder
    var body: some Widget {
        AIWellnessWidget()
        IntentionWidget()
        HabitWidget()
        // Life-toolkit tool widgets (9 small square shortcuts).
        lifeToolWidgets
    }

    // Grouped separately so the top-level bundle stays within the
    // WidgetBundleBuilder arity limit.
    @WidgetBundleBuilder
    private var lifeToolWidgets: some Widget {
        NutritionToolWidget()
        MealPlannerToolWidget()
        CalorieBudgetToolWidget()
        HydrationToolWidget()
        SleepToolWidget()
        MeditationToolWidget()
        PeriodTrackerToolWidget()
        WeightTrackerToolWidget()
        MindfulTravelToolWidget()
    }
}
