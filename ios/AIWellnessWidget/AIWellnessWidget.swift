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

// MARK: - Day rollover

/// Swift twin of Android's WidgetDay.kt. The app stamps each date-scoped
/// snapshot with the day it was written (`<tool>_date`, yyyy-MM-dd); when an
/// entry is for a later day, these overlay what the app would show that day:
/// totals reset (hydration, nutrition, calories), period cycle recomputed,
/// yesterday's plan → placeholder, today's habits unchecked. Snapshots without
/// a stamp (older app builds) are shown as-is. Each timeline also carries an
/// entry dated next midnight (see `timelineDates`) so the roll-over happens on
/// time without the app running.
struct WidgetDayDefaults {
    let base: UserDefaults
    let over: [String: Any]
    func integer(forKey k: String) -> Int { over.keys.contains(k) ? (over[k] as? Int ?? 0) : base.integer(forKey: k) }
    func string(forKey k: String) -> String? { over.keys.contains(k) ? over[k] as? String : base.string(forKey: k) }
    func bool(forKey k: String) -> Bool { over.keys.contains(k) ? (over[k] as? Bool ?? false) : base.bool(forKey: k) }
}

enum WidgetDay {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static var defaults: UserDefaults? { UserDefaults(suiteName: kWidgetAppGroup) }

    /// Now, plus the start of tomorrow — one timeline entry for each.
    static func timelineDates(from now: Date = Date()) -> [Date] {
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return [now, midnight]
    }

    private static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty, let d = fmt.date(from: s) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    private static func isStale(_ d: UserDefaults, _ key: String, at date: Date) -> Bool {
        guard let stamp = parse(d.string(forKey: key)) else { return false }
        return stamp < Calendar.current.startOfDay(for: date)
    }

    private static func view(_ over: (UserDefaults) -> [String: Any]) -> WidgetDayDefaults? {
        guard let d = defaults else { return nil }
        return WidgetDayDefaults(base: d, over: over(d))
    }

    static func hydration(at date: Date) -> WidgetDayDefaults? {
        view { d in isStale(d, "hydration_date", at: date)
            ? ["hydration_consumed_ml": 0, "hydration_pct": 0] : [:] }
    }

    static func nutrition(at date: Date) -> WidgetDayDefaults? {
        view { d in isStale(d, "nutrition_date", at: date)
            ? ["nutrition_calories": 0, "nutrition_pct": 0, "nutrition_protein": 0,
               "nutrition_carbs": 0, "nutrition_fat": 0, "nutrition_meal_count": 0] : [:] }
    }

    static func calorieBudget(at date: Date) -> WidgetDayDefaults? {
        view { d in isStale(d, "calorie_date", at: date)
            ? ["calorie_consumed": 0, "calorie_burned": 0, "calorie_pct": 0,
               "calorie_remaining": d.integer(forKey: "calorie_budget")] : [:] }
    }

    static func plan(at date: Date) -> WidgetDayDefaults? {
        view { d in isStale(d, "wellness_plan_date", at: date) ? ["wellness_placeholder": true] : [:] }
    }

    /// Period values for [date], mirroring PeriodData's getters exactly.
    static func period(at date: Date) -> WidgetDayDefaults? {
        view { d in
            guard let last = parse(d.string(forKey: "period_last_start")) else { return [:] }
            let cal = Calendar.current
            let rawLen = d.integer(forKey: "period_cycle_length")
            let len = max(1, rawLen > 0 ? rawLen : 28)
            let rawPeriod = d.integer(forKey: "period_length")
            let periodLength = rawPeriod > 0 ? rawPeriod : 5
            let today = cal.startOfDay(for: date)
            let diff = cal.dateComponents([.day], from: last, to: today).day ?? 0
            let day = ((diff % len) + len) % len + 1
            let next = cal.date(byAdding: .day, value: len, to: last) ?? last
            let daysUntil = cal.dateComponents([.day], from: today, to: next).day ?? 0
            let ovDay = len - 14
            let (label, emoji): (String, String)
            if day <= periodLength { (label, emoji) = ("Menstrual", "🌸") }
            else if abs(day - ovDay) <= 1 { (label, emoji) = ("Ovulation", "🌼") }
            else if day < ovDay { (label, emoji) = ("Follicular", "🌱") }
            else { (label, emoji) = ("Luteal", "🌙") }
            return ["period_has_data": true, "period_cycle_day": day,
                    "period_days_until_next": daysUntil, "period_phase": label, "period_emoji": emoji]
        }
    }

    /// On a new day: that day's scheduled habits (from `habit_schedule_json`),
    /// none completed — the same first-two rows the app writes.
    static func habits(at date: Date) -> WidgetDayDefaults? {
        view { d in
            guard isStale(d, "habit_date", at: date),
                  let json = d.string(forKey: "habit_schedule_json")?.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]]
            else { return [:] }
            // Calendar weekday is Sun=1…Sat=7; the app uses Mon=1…Sun=7.
            let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
            let scheduled = list.filter { h in
                let days = h["days"] as? [Int] ?? []
                switch h["freq"] as? String {
                case "daily": return true
                case "weekdays": return weekday <= 5
                case "weekends": return weekday >= 6
                case "custom": return days.contains(weekday)
                default: return false
                }
            }
            var over: [String: Any] = [
                "habit_has_habits": !scheduled.isEmpty, "habit_all_done": false,
                "habit_count": min(2, scheduled.count), "habit_completed": 0,
                "habit_total": scheduled.count, "habit_progress": 0,
            ]
            for i in 0..<2 {
                let h = i < scheduled.count ? scheduled[i] : nil
                over["habit_\(i + 1)_id"] = h?["id"] as? String ?? ""
                over["habit_\(i + 1)_text"] = h?["title"] as? String ?? ""
                over["habit_\(i + 1)_emoji"] = h?["emoji"] as? String ?? ""
                over["habit_\(i + 1)_checked"] = false
            }
            return over
        }
    }
}

/// Whether a specific widget should render in its dark theme. Each widget owns
/// its own theme, stored in the shared app group under
/// `widget_theme_dark_<widgetId>` and flipped independently from Dart's
/// `backgroundCallback` (`widget_theme_toggle?w=<widgetId>`). This is a manual
/// in-widget toggle (see `WidgetThemeToggleButton`) rather than the system
/// appearance, because WidgetKit does not reliably re-render a placed widget's
/// cached image rendition when the system light/dark mode changes.
func widgetThemeIsDark(_ widgetId: String) -> Bool {
    UserDefaults(suiteName: kWidgetAppGroup)?.bool(forKey: "widget_theme_dark_\(widgetId)") ?? false
}

/// Primary text color that follows a widget's manual theme (dark text on the
/// light chip, light text on the dark chip). Using a fixed color per theme —
/// rather than `.primary` — keeps text readable even when the manual theme
/// differs from the system appearance.
func widgetTextColor(_ widgetId: String) -> Color {
    widgetThemeIsDark(widgetId) ? Color.white : Color(red: 0.11, green: 0.12, blue: 0.15)
}

/// Secondary/dimmed text color for a widget's current manual theme.
func widgetSecondaryTextColor(_ widgetId: String) -> Color {
    widgetThemeIsDark(widgetId)
        ? Color.white.opacity(0.75)
        : Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.6)
}

/// A small sun/moon button, placed in the top-right of each widget, that flips
/// THAT widget's manual light/dark theme independently. Tapping fires the
/// shared `BackgroundIntent` with `widget_theme_toggle?w=<widgetId>`, which
/// Dart handles by flipping `widget_theme_dark_<widgetId>` and re-pushing only
/// that widget.
struct WidgetThemeToggleButton: View {
    var isDark: Bool
    /// The owning widget's id (e.g. "plan", "intention", "habit",
    /// "tool_nutrition"). Determines which per-widget theme key is flipped.
    var widgetId: String

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
        let encoded = widgetId.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? widgetId
        let url = URL(string: "aiwellnesspal://widget_theme_toggle?w=\(encoded)")
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
    func widgetBackgroundImage(_ baseName: String, widgetId: String) -> some View {
        modifier(WidgetBackgroundImageModifier(baseName: baseName, widgetId: widgetId))
    }
}

/// Picks the light/dark background image from the owning widget's manual theme
/// stored in the app group (see `widgetThemeIsDark(_:)`), not system appearance.
private struct WidgetBackgroundImageModifier: ViewModifier {
    let baseName: String
    let widgetId: String

    private var asset: String { "\(baseName)_\(widgetThemeIsDark(widgetId) ? "dark" : "light")" }

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
    /// Owning widget id, so the chip fill follows that widget's own theme.
    let widgetId: String
    let content: Content
    init(_ widgetId: String, @ViewBuilder _ content: () -> Content) {
        self.widgetId = widgetId
        self.content = content()
    }

    /// Chosen from the owning widget's manual theme (app group), so it flips
    /// together with the background: near-white in light, dark in dark.
    private var fill: Color {
        widgetThemeIsDark(widgetId)
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
        // Now + next midnight, so yesterday's plan clears on time.
        let entries = WidgetDay.timelineDates().map { loadEntry(at: $0) }
        // Refresh every 30 minutes (matches the Dart-side 30-min cap).
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadEntry(at date: Date = Date()) -> WellnessEntry {
        guard let defaults = WidgetDay.plan(at: date) else {
            return placeholderEntry(date)
        }

        let isPlaceholder = defaults.bool(forKey: "wellness_placeholder")
        if isPlaceholder {
            return placeholderEntry(date)
        }

        let planId = defaults.string(forKey: "wellness_plan_id") ?? ""
        let focus = defaults.string(forKey: "wellness_focus") ?? "Today's Focus"

        return WellnessEntry(
            date: date,
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

    private func placeholderEntry(_ date: Date = Date()) -> WellnessEntry {
        WellnessEntry(
            date: date,
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

    /// Per-widget theme id (independent light/dark).
    private let wid = "plan"

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
            WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid)
                .padding(10)
        }
        .widgetBackgroundImage("bg_todays_plan", widgetId: wid)
        // Tapping anywhere outside the interactive buttons opens the app on the
        // Home (daily plan) tab. `homeWidget` query item required (see
        // HabitWidget for the rationale).
        .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=home"))
    }

    private var placeholderView: some View {
        VStack {
            Spacer()
            WidgetChip(wid) {
                Text("Open the app to start your wellness day.")
                    .font(.subheadline)
                    .foregroundColor(widgetTextColor(wid))
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
                WidgetChip(wid) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .foregroundColor(Color("WidgetPrimary"))
                        Text("All actions complete 🎉")
                            .font(.subheadline)
                            .foregroundColor(widgetSecondaryTextColor(wid))
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
                WidgetChip(wid) { rowContent(task) }
            }
            .buttonStyle(.plain)
        } else {
            WidgetChip(wid) { rowContent(task) }
        }
        #else
        WidgetChip(wid) { rowContent(task) }
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
                .strikethrough(task.checked, color: widgetSecondaryTextColor(wid))
                .foregroundColor(task.checked ? widgetSecondaryTextColor(wid) : widgetTextColor(wid))
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
        // Live-data widgets first, then the simple shortcut tiles
        // (Sleep, Meditation, Mindful Travel) last in the gallery.
        HydrationToolWidget()
        NutritionToolWidget()
        MealPlannerToolWidget()
        CalorieBudgetToolWidget()
        PeriodTrackerToolWidget()
        WeightTrackerToolWidget()
        SleepToolWidget()
        MeditationToolWidget()
        MindfulTravelToolWidget()
    }
}
