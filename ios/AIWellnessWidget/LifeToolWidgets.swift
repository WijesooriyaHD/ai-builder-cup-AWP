import WidgetKit
import SwiftUI

// MARK: - Life-toolkit tool widgets
//
// Nine small, square, non-resizable widgets — one per Life-toolkit tool. Each
// shows the tool's emoji and label (mirroring the in-app "Jump to tool" grid)
// and opens the app to that tool via a `.widgetURL` deep link:
//   aiwellnesspal://open?homeWidget=1&screen=tool_<id>
//
// The `homeWidget` query item is required for the home_widget plugin to
// recognize the launch URL (see the note in the other widget files). The Dart
// side (MainWrapper._handleWidgetUri) maps `tool_<id>` to the tool screen.

extension Color {
    /// Builds a Color from a 6-digit RRGGBB hex string (matches the in-app
    /// tool accent colors).
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// Static description of a Life-toolkit tool shown as a widget.
struct LifeToolInfo {
    let id: String
    let emoji: String
    let label: String
    /// Accent color (matches the in-app "Jump to tool" tile), used as a soft
    /// tinted background so each widget visually matches its emoji.
    let accent: Color
}

/// A single small square tool tile: big emoji + label, on the shared themed
/// chip background so it stays readable in light and dark.
struct LifeToolWidgetView: View {
    let tool: LifeToolInfo

    /// Per-widget theme id (independent light/dark), namespaced per tool.
    private var wid: String { "tool_\(tool.id)" }

    private var textColor: Color { widgetTextColor(wid) }

    var body: some View {
        VStack(spacing: 8) {
            Text(tool.emoji)
                .font(.system(size: 40))
            Text(tool.label)
                .font(.caption).bold()
                .multilineTextAlignment(.center)
                .foregroundColor(textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid)
                .padding(6)
        }
        .modifier(LifeToolBackground(accent: tool.accent, widgetId: wid))
        .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_\(tool.id)"))
    }
}

/// Full-bleed soft tinted background for a tool tile: the tool's accent color
/// blended over the themed base so each widget matches its emoji while staying
/// readable in light and dark.
private struct LifeToolBackground: ViewModifier {
    let accent: Color
    let widgetId: String

    private var base: Color {
        widgetThemeIsDark(widgetId)
            ? Color(red: 0.118, green: 0.145, blue: 0.180)
            : Color.white
    }

    /// Soft tint: gentle in light mode, a touch stronger in dark mode.
    private var tintOpacity: Double { widgetThemeIsDark(widgetId) ? 0.30 : 0.16 }

    @ViewBuilder
    private var fill: some View {
        base.overlay(accent.opacity(tintOpacity))
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { fill }
        } else {
            content.background(fill)
        }
    }
}

/// Shared timeline provider — the tool tiles are static, so a single entry is
/// enough. Each widget passes its own [LifeToolInfo].
struct LifeToolProvider: TimelineProvider {
    let tool: LifeToolInfo

    func placeholder(in context: Context) -> LifeToolEntry {
        LifeToolEntry(date: Date(), tool: tool)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeToolEntry) -> Void) {
        completion(LifeToolEntry(date: Date(), tool: tool))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeToolEntry>) -> Void) {
        // Refresh occasionally so the manual theme change is picked up.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [LifeToolEntry(date: Date(), tool: tool)], policy: .after(next)))
    }
}

struct LifeToolEntry: TimelineEntry {
    let date: Date
    let tool: LifeToolInfo
}

// MARK: - Concrete widgets (one per tool)

struct NutritionToolWidget: Widget {
    private let tool = LifeToolInfo(id: "nutrition", emoji: "🥗", label: "Nutrition Coach", accent: Color(hex: 0x57B894))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NutritionToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Nutrition Coach")
        .description("Open the Nutrition Coach tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct MealPlannerToolWidget: Widget {
    private let tool = LifeToolInfo(id: "meal_planner", emoji: "🍽️", label: "Meal Planner", accent: Color(hex: 0xEF8354))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealPlannerToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Meal Planner")
        .description("Open the Meal Planner tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct CalorieBudgetToolWidget: Widget {
    private let tool = LifeToolInfo(id: "calorie_budget", emoji: "🔥", label: "Calorie Budget", accent: Color(hex: 0xF5A623))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalorieBudgetToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Calorie Budget")
        .description("Open the Calorie Budget tool.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Hydration (live data + flip-to-progress-ring)
//
// Unlike the other tool tiles, the Hydration widget shows live data written by
// the app into the shared app group (see HydrationState.syncHydrationWidget in
// Dart). Default face = standard emoji + label tile. Flip button swaps to a
// live water-fill progress ring showing today's consumed / goal. The flip state
// is persisted per-widget under `hydration_flipped_tool_hydration` and toggled
// via the shared BackgroundIntent (`aiwellnesspal://hydration_flip`). The ring
// is shown immediately on flip — even before the app has been opened — using a
// dashed placeholder arc until real data is synced.

private let kHydrationAccent = Color(hex: 0x3FA9F5)

struct HydrationEntry: TimelineEntry {
    let date: Date
    let pct: Int          // 0..100 today's completion
    let consumedMl: Int
    let goalMl: Int
    let flipped: Bool     // showing the data (progress ring) face
}

struct HydrationProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_hydration"

    func placeholder(in context: Context) -> HydrationEntry {
        // Gallery/placeholder shows the default tile (not flipped).
        HydrationEntry(date: Date(), pct: 0, consumedMl: 0, goalMl: 0, flipped: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (HydrationEntry) -> Void) {
        // In the widget gallery ("Add Widget"), always show the default tile
        // (emoji + title) so it looks consistent with the other tool widgets —
        // regardless of any persisted flip state.
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> HydrationEntry {
        let d = defaults
        return HydrationEntry(
            date: Date(),
            pct: d?.integer(forKey: "hydration_pct") ?? 0,
            consumedMl: d?.integer(forKey: "hydration_consumed_ml") ?? 0,
            goalMl: d?.integer(forKey: "hydration_goal_ml") ?? 0,
            flipped: d?.bool(forKey: "hydration_flipped_\(wid)") ?? false
        )
    }
}

/// A small circular button that flips the Hydration widget between its default
/// tile (emoji + title) and the progress-ring data face. Fires the shared
/// BackgroundIntent, which Dart handles headlessly (no app launch needed).
struct HydrationFlipButton: View {
    var flipped: Bool
    private let wid = "tool_hydration"

    var body: some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: flipIntent()) { icon }
                .buttonStyle(.plain)
        } else { icon }
        #else
        icon
        #endif
    }

    private var icon: some View {
        Image(systemName: "arrow.2.squarepath")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(kHydrationAccent)
            .padding(6)
            .background(Circle().fill(Color.white.opacity(0.9)))
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func flipIntent() -> BackgroundIntent {
        let url = URL(string: "aiwellnesspal://hydration_flip?w=\(wid)")
        return BackgroundIntent(url: url, appGroup: kWidgetAppGroup)
    }
    #endif
}

/// Water-fill progress ring (data face).
/// Shows a dashed track and "–" for goal on a fresh install before the app
/// has been opened — so the flip works immediately without requiring the app
/// to be launched first.
private struct HydrationRing: View {
    let entry: HydrationEntry
    let textColor: Color

    private var hasData: Bool { entry.goalMl > 0 }

    var body: some View {
        let fraction = min(max(Double(entry.pct) / 100.0, 0), 1)
        return VStack(spacing: 6) {
            // Push the ring down so it clears the flip/theme toggle buttons.
            Spacer().frame(height: 18)
            ZStack {
                // Track: dashed when no data yet, solid otherwise.
                Circle()
                    .stroke(
                        kHydrationAccent.opacity(hasData ? 0.15 : 0.10),
                        style: hasData
                            ? StrokeStyle(lineWidth: 8)
                            : StrokeStyle(lineWidth: 8, dash: [4, 4])
                    )
                // Progress arc — only when we have real data.
                if hasData {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(kHydrationAccent,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(hasData ? "\(entry.pct)%" : "💧")
                        .font(.system(size: hasData ? 20 : 24, weight: .bold))
                        .foregroundColor(kHydrationAccent)
                    if hasData {
                        Text("💧").font(.system(size: 12))
                    }
                }
            }
            .frame(width: 74, height: 74)

            Text(hasData
                 ? "\(mlText(entry.consumedMl)) / \(mlText(entry.goalMl))"
                 : "Open app to sync")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func mlText(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.1fL", Double(ml) / 1000.0) : "\(ml)ml"
    }
}

struct HydrationToolWidgetView: View {
    var entry: HydrationEntry
    private let wid = "tool_hydration"
    private var textColor: Color { widgetTextColor(wid) }

    private var base: Color {
        widgetThemeIsDark(wid) ? Color(red: 0.118, green: 0.145, blue: 0.180) : Color.white
    }
    private var tintOpacity: Double { widgetThemeIsDark(wid) ? 0.30 : 0.16 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                HydrationFlipButton(flipped: entry.flipped).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid)
                    .padding(6)
            }
            .modifier(HydrationBackground(base: base, tintOpacity: tintOpacity))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_hydration"))
    }

    // Default (not flipped) → the standard tool tile: emoji + title, identical
    // to the other Life-toolkit widgets and what shows in the "Add Widget"
    // gallery. Flipped → the live progress ring + consumed/goal. The ring
    // shows 0% / goal with an empty arc on a fresh install before any data
    // has been synced — the callback flip works immediately without needing
    // the app to be opened first.
    @ViewBuilder
    private var content: some View {
        if entry.flipped {
            HydrationRing(entry: entry, textColor: textColor)
        } else {
            defaultTile
        }
    }

    private var defaultTile: some View {
        VStack(spacing: 8) {
            Text("💧").font(.system(size: 40))
            Text("Hydration Coach")
                .font(.caption).bold()
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }
}

private struct HydrationBackground: ViewModifier {
    let base: Color
    let tintOpacity: Double

    @ViewBuilder private var fill: some View {
        base.overlay(kHydrationAccent.opacity(tintOpacity))
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { fill }
        } else {
            content.background(fill)
        }
    }
}

struct HydrationToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HydrationToolWidget", provider: HydrationProvider()) { entry in
            HydrationToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Hydration Coach")
        .description("Tap the flip button to see today's water progress.")
        .supportedFamilies([.systemSmall])
    }
}

struct SleepToolWidget: Widget {
    private let tool = LifeToolInfo(id: "sleep", emoji: "🌙", label: "Sleep Coach", accent: Color(hex: 0x6C63FF))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Sleep Coach")
        .description("Open the Sleep Coach tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct MeditationToolWidget: Widget {
    private let tool = LifeToolInfo(id: "meditation", emoji: "🧘", label: "Meditation Pal", accent: Color(hex: 0x9B59B6))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeditationToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Meditation Pal")
        .description("Open the Meditation Pal tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct PeriodTrackerToolWidget: Widget {
    private let tool = LifeToolInfo(id: "period_tracker", emoji: "🌸", label: "Period Tracker", accent: Color(hex: 0xE9506E))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeriodTrackerToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Period Tracker")
        .description("Open the Period Tracker tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct WeightTrackerToolWidget: Widget {
    private let tool = LifeToolInfo(id: "weight_tracker", emoji: "⚖️", label: "Body Weight", accent: Color(hex: 0x2ECC71))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightTrackerToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Body Weight")
        .description("Open the Body Weight tool.")
        .supportedFamilies([.systemSmall])
    }
}

struct MindfulTravelToolWidget: Widget {
    private let tool = LifeToolInfo(id: "mindful_travel", emoji: "✈️", label: "Mindful Travel", accent: Color(hex: 0x3A7BD5))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MindfulTravelToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Mindful Travel")
        .description("Open the Mindful Travel tool.")
        .supportedFamilies([.systemSmall])
    }
}
