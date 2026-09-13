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

struct HydrationToolWidget: Widget {
    private let tool = LifeToolInfo(id: "hydration", emoji: "💧", label: "Hydration Coach", accent: Color(hex: 0x3FA9F5))
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HydrationToolWidget", provider: LifeToolProvider(tool: tool)) { entry in
            LifeToolWidgetView(tool: entry.tool)
        }
        .configurationDisplayName("Hydration Coach")
        .description("Open the Hydration Coach tool.")
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
