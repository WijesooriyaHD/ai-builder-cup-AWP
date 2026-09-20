import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Live-data tool widgets
//
// Nutrition Coach, AI Meal Planner, Calorie Budget, Period Tracker and Body
// Weight each mirror the Hydration widget pattern: a default emoji + title tile
// (identical to the other shortcut widgets and the "Add Widget" gallery) with a
// flip button that reveals a live-data face. Data is written by the Dart state
// classes into the shared app group; flip state is per-widget under
// `flipped_<widgetId>` and toggled via the shared BackgroundIntent
// (`aiwellnesspal://tool_flip?w=<widgetId>&kind=<WidgetKind>`). The Meal Planner
// additionally has up/down arrows that cycle `meal_index_<widgetId>` via
// `aiwellnesspal://meal_index?w=<widgetId>&dir=±1`.
//
// WidgetKit renders static snapshots on the home screen (no live animation), so
// the flip is a tap-to-swap between faces — consistent with Hydration.

// MARK: - Shared flip button

/// A small circular flip button shared by all live-data tool widgets. Fires the
/// generic `tool_flip` BackgroundIntent for the given widget id + kind.
struct ToolFlipButton: View {
    let widgetId: String
    let kind: String
    let accent: Color

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
            .foregroundColor(accent)
            .padding(6)
            .background(Circle().fill(Color.white.opacity(0.9)))
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func flipIntent() -> BackgroundIntent {
        let w = widgetId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? widgetId
        let k = kind.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kind
        let url = URL(string: "aiwellnesspal://tool_flip?w=\(w)&kind=\(k)")
        return BackgroundIntent(url: url, appGroup: kWidgetAppGroup)
    }
    #endif
}

/// Full-bleed soft-tinted background matching a tool's accent + manual theme.
struct LiveToolBackgroundModifier: ViewModifier {
    let accent: Color
    let widgetId: String

    private var base: Color {
        widgetThemeIsDark(widgetId)
            ? Color(red: 0.118, green: 0.145, blue: 0.180)
            : Color.white
    }
    private var tintOpacity: Double { widgetThemeIsDark(widgetId) ? 0.30 : 0.16 }

    @ViewBuilder private var fill: some View {
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

/// Default emoji + title tile, shared by all live-data widgets.
struct ToolDefaultTile: View {
    let emoji: String
    let label: String
    let widgetId: String

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 40))
            Text(label)
                .font(.caption).bold()
                .foregroundColor(widgetTextColor(widgetId))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }
}

/// Shared circular progress ring used by Nutrition, Calorie and Period faces.
struct ToolRing: View {
    let fraction: Double        // 0...1 (may exceed for over-budget; clamped)
    let accent: Color
    let hasData: Bool
    let centerTop: String       // big text (e.g. "62%", "540", "Luteal")
    let centerBottom: String    // small text under it (emoji or label)
    let centerTopSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    accent.opacity(hasData ? 0.15 : 0.10),
                    style: hasData
                        ? StrokeStyle(lineWidth: 8)
                        : StrokeStyle(lineWidth: 8, dash: [4, 4])
                )
            if hasData {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(centerTop)
                    .font(.system(size: centerTopSize, weight: .bold))
                    .foregroundColor(accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !centerBottom.isEmpty {
                    Text(centerBottom).font(.system(size: 11))
                }
            }
        }
        .frame(width: 88, height: 88)
    }
}

// MARK: - 1. Nutrition Coach → Today's Progress

private let kNutritionAccent = Color(hex: 0x57B894)

struct NutritionEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let goal: Int
    let pct: Int
    let protein: Int, proteinGoal: Int
    let carbs: Int, carbsGoal: Int
    let fat: Int, fatGoal: Int
    let flipped: Bool
}

struct NutritionProvider: TimelineProvider {
    private let d = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_nutrition"

    func placeholder(in context: Context) -> NutritionEntry { load(flippedOverride: false) }
    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(context.isPreview ? load(flippedOverride: false) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load(flippedOverride: Bool? = nil) -> NutritionEntry {
        NutritionEntry(
            date: Date(),
            calories: d?.integer(forKey: "nutrition_calories") ?? 0,
            goal: d?.integer(forKey: "nutrition_calorie_goal") ?? 0,
            pct: d?.integer(forKey: "nutrition_pct") ?? 0,
            protein: d?.integer(forKey: "nutrition_protein") ?? 0,
            proteinGoal: d?.integer(forKey: "nutrition_protein_goal") ?? 0,
            carbs: d?.integer(forKey: "nutrition_carbs") ?? 0,
            carbsGoal: d?.integer(forKey: "nutrition_carbs_goal") ?? 0,
            fat: d?.integer(forKey: "nutrition_fat") ?? 0,
            fatGoal: d?.integer(forKey: "nutrition_fat_goal") ?? 0,
            flipped: flippedOverride ?? (d?.bool(forKey: "flipped_\(wid)") ?? false)
        )
    }
}

struct NutritionToolWidgetView: View {
    var entry: NutritionEntry
    private let wid = "tool_nutrition"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ToolFlipButton(widgetId: wid, kind: "NutritionToolWidget", accent: kNutritionAccent).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid).padding(6)
            }
            .modifier(LiveToolBackgroundModifier(accent: kNutritionAccent, widgetId: wid))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_nutrition"))
    }

    @ViewBuilder private var content: some View {
        if entry.flipped {
            let hasData = entry.goal > 0
            VStack(spacing: 8) {
                Spacer().frame(height: 12)
                ToolRing(
                    fraction: hasData ? Double(entry.pct) / 100.0 : 0,
                    accent: kNutritionAccent, hasData: hasData,
                    centerTop: hasData ? "\(entry.calories)" : "🥗",
                    centerBottom: hasData ? "/ \(entry.goal) kcal" : "",
                    centerTopSize: 20)
                if hasData {
                    HStack(spacing: 8) {
                        macro("P", entry.protein, entry.proteinGoal)
                        macro("C", entry.carbs, entry.carbsGoal)
                        macro("F", entry.fat, entry.fatGoal)
                    }
                } else {
                    Text("Open app to sync")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                }
            }
            .padding(.horizontal, 8)
        } else {
            ToolDefaultTile(emoji: "🥗", label: "Nutrition Coach", widgetId: wid)
        }
    }

    private func macro(_ label: String, _ v: Int, _ goal: Int) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(kNutritionAccent)
            Text("\(v)g").font(.system(size: 10, weight: .semibold)).foregroundColor(widgetTextColor(wid))
        }
    }
}

struct NutritionToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NutritionToolWidget", provider: NutritionProvider()) { entry in
            NutritionToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Nutrition Coach")
        .description("Tap flip to see today's calories & macros.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 2. AI Meal Planner → Today's meals (one at a time)

private let kMealAccent = Color(hex: 0xEF8354)

struct MealPlannerEntry: TimelineEntry {
    let date: Date
    let count: Int
    let index: Int
    let name: String
    let type: String
    let cal: Int
    let flipped: Bool
}

struct MealPlannerProvider: TimelineProvider {
    private let d = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_meal_planner"

    func placeholder(in context: Context) -> MealPlannerEntry { load(flippedOverride: false) }
    func getSnapshot(in context: Context, completion: @escaping (MealPlannerEntry) -> Void) {
        completion(context.isPreview ? load(flippedOverride: false) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MealPlannerEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load(flippedOverride: Bool? = nil) -> MealPlannerEntry {
        let count = d?.integer(forKey: "meal_count") ?? 0
        var idx = d?.integer(forKey: "meal_index_\(wid)") ?? 0
        if count > 0 { idx = ((idx % count) + count) % count } else { idx = 0 }
        return MealPlannerEntry(
            date: Date(),
            count: count,
            index: idx,
            name: d?.string(forKey: "meal_\(idx)_name") ?? "",
            type: d?.string(forKey: "meal_\(idx)_type") ?? "",
            cal: d?.integer(forKey: "meal_\(idx)_cal") ?? 0,
            flipped: flippedOverride ?? (d?.bool(forKey: "flipped_\(wid)") ?? false)
        )
    }
}

struct MealPlannerToolWidgetView: View {
    var entry: MealPlannerEntry
    private let wid = "tool_meal_planner"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ToolFlipButton(widgetId: wid, kind: "MealPlannerToolWidget", accent: kMealAccent).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid).padding(6)
            }
            .modifier(LiveToolBackgroundModifier(accent: kMealAccent, widgetId: wid))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_meal_planner"))
    }

    @ViewBuilder private var content: some View {
        if entry.flipped {
            if entry.count > 0 && !entry.name.isEmpty {
                HStack(spacing: 4) {
                    // The meal card.
                    VStack(spacing: 4) {
                        Spacer().frame(height: 10)
                        Text(entry.type.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(kMealAccent)
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(widgetTextColor(wid))
                            .multilineTextAlignment(.center)
                            .lineLimit(3).minimumScaleFactor(0.7)
                        Text("\(entry.cal) kcal")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(widgetTextColor(wid))
                        Text("\(entry.index + 1) / \(entry.count)")
                            .font(.system(size: 9))
                            .foregroundColor(widgetTextColor(wid).opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    // Up/down arrows.
                    VStack(spacing: 10) {
                        mealArrow(systemName: "chevron.up", dir: -1)
                        mealArrow(systemName: "chevron.down", dir: 1)
                    }
                    .padding(.trailing, 2)
                }
                .padding(.horizontal, 6)
            } else {
                VStack(spacing: 6) {
                    Text("🍽️").font(.system(size: 32))
                    Text("No plan yet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                    Text("Open app to generate")
                        .font(.system(size: 9))
                        .foregroundColor(widgetTextColor(wid).opacity(0.6))
                }
            }
        } else {
            ToolDefaultTile(emoji: "🍽️", label: "Meal Planner", widgetId: wid)
        }
    }

    @ViewBuilder
    private func mealArrow(systemName: String, dir: Int) -> some View {
        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Button(intent: indexIntent(dir: dir)) { arrowIcon(systemName) }
                .buttonStyle(.plain)
        } else { arrowIcon(systemName) }
        #else
        arrowIcon(systemName)
        #endif
    }

    private func arrowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(kMealAccent)
            .padding(6)
            .background(Circle().fill(Color.white.opacity(0.9)))
    }

    #if canImport(AppIntents)
    @available(iOS 17.0, *)
    private func indexIntent(dir: Int) -> BackgroundIntent {
        let url = URL(string: "aiwellnesspal://meal_index?w=\(wid)&dir=\(dir)")
        return BackgroundIntent(url: url, appGroup: kWidgetAppGroup)
    }
    #endif
}

struct MealPlannerToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealPlannerToolWidget", provider: MealPlannerProvider()) { entry in
            MealPlannerToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Meal Planner")
        .description("Tap flip to see today's meals — use the arrows to browse.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 3. Calorie Budget → kcal-remaining ring

private let kCalorieAccent = Color(hex: 0xF5A623)

struct CalorieEntry: TimelineEntry {
    let date: Date
    let budget: Int
    let consumed: Int
    let burned: Int
    let remaining: Int
    let pct: Int
    let flipped: Bool
}

struct CalorieProvider: TimelineProvider {
    private let d = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_calorie_budget"

    func placeholder(in context: Context) -> CalorieEntry { load(flippedOverride: false) }
    func getSnapshot(in context: Context, completion: @escaping (CalorieEntry) -> Void) {
        completion(context.isPreview ? load(flippedOverride: false) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load(flippedOverride: Bool? = nil) -> CalorieEntry {
        CalorieEntry(
            date: Date(),
            budget: d?.integer(forKey: "calorie_budget") ?? 0,
            consumed: d?.integer(forKey: "calorie_consumed") ?? 0,
            burned: d?.integer(forKey: "calorie_burned") ?? 0,
            remaining: d?.integer(forKey: "calorie_remaining") ?? 0,
            pct: d?.integer(forKey: "calorie_pct") ?? 0,
            flipped: flippedOverride ?? (d?.bool(forKey: "flipped_\(wid)") ?? false)
        )
    }
}

struct CalorieBudgetToolWidgetView: View {
    var entry: CalorieEntry
    private let wid = "tool_calorie_budget"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ToolFlipButton(widgetId: wid, kind: "CalorieBudgetToolWidget", accent: kCalorieAccent).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid).padding(6)
            }
            .modifier(LiveToolBackgroundModifier(accent: kCalorieAccent, widgetId: wid))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_calorie_budget"))
    }

    @ViewBuilder private var content: some View {
        if entry.flipped {
            let hasData = entry.budget > 0
            let over = entry.remaining < 0
            VStack(spacing: 6) {
                Spacer().frame(height: 12)
                ToolRing(
                    fraction: hasData ? Double(entry.pct) / 100.0 : 0,
                    accent: over ? Color(hex: 0xE9506E) : kCalorieAccent,
                    hasData: hasData,
                    centerTop: hasData ? "\(entry.remaining)" : "🔥",
                    centerBottom: hasData ? "kcal left" : "",
                    centerTopSize: 22)
                if hasData {
                    Text("\(entry.consumed) eaten · \(entry.budget) budget")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("Open app to sync")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                }
            }
            .padding(.horizontal, 8)
        } else {
            ToolDefaultTile(emoji: "🔥", label: "Calorie Budget", widgetId: wid)
        }
    }
}

struct CalorieBudgetToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalorieBudgetToolWidget", provider: CalorieProvider()) { entry in
            CalorieBudgetToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Calorie Budget")
        .description("Tap flip to see kcal remaining today.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 4. Period Tracker → cycle-phase ring

private let kPeriodAccent = Color(hex: 0xE9506E)

struct PeriodEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    let phase: String
    let emoji: String
    let cycleDay: Int
    let cycleLength: Int
    let daysUntilNext: Int
    let flipped: Bool
}

struct PeriodProvider: TimelineProvider {
    private let d = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_period_tracker"

    func placeholder(in context: Context) -> PeriodEntry { load(flippedOverride: false) }
    func getSnapshot(in context: Context, completion: @escaping (PeriodEntry) -> Void) {
        completion(context.isPreview ? load(flippedOverride: false) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PeriodEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 60, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load(flippedOverride: Bool? = nil) -> PeriodEntry {
        PeriodEntry(
            date: Date(),
            hasData: d?.bool(forKey: "period_has_data") ?? false,
            phase: d?.string(forKey: "period_phase") ?? "",
            emoji: d?.string(forKey: "period_emoji") ?? "🌸",
            cycleDay: d?.integer(forKey: "period_cycle_day") ?? 0,
            cycleLength: d?.integer(forKey: "period_cycle_length") ?? 28,
            daysUntilNext: d?.integer(forKey: "period_days_until_next") ?? -999,
            flipped: flippedOverride ?? (d?.bool(forKey: "flipped_\(wid)") ?? false)
        )
    }
}

struct PeriodTrackerToolWidgetView: View {
    var entry: PeriodEntry
    private let wid = "tool_period_tracker"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ToolFlipButton(widgetId: wid, kind: "PeriodTrackerToolWidget", accent: kPeriodAccent).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid).padding(6)
            }
            .modifier(LiveToolBackgroundModifier(accent: kPeriodAccent, widgetId: wid))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_period_tracker"))
    }

    @ViewBuilder private var content: some View {
        if entry.flipped {
            let hasData = entry.hasData && entry.cycleLength > 0
            let frac = hasData ? Double(entry.cycleDay) / Double(entry.cycleLength) : 0
            VStack(spacing: 6) {
                Spacer().frame(height: 12)
                ToolRing(
                    fraction: frac, accent: kPeriodAccent, hasData: hasData,
                    centerTop: hasData ? entry.emoji : "🌸",
                    centerBottom: hasData ? "Day \(entry.cycleDay)" : "",
                    centerTopSize: 24)
                if hasData {
                    Text(entry.phase)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(kPeriodAccent)
                    Text(nextText(entry.daysUntilNext))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("Open app to sync")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                }
            }
            .padding(.horizontal, 8)
        } else {
            ToolDefaultTile(emoji: "🌸", label: "Period Tracker", widgetId: wid)
        }
    }

    private func nextText(_ days: Int) -> String {
        if days == -999 { return "" }
        if days < 0 { return "\(-days)d late" }
        if days == 0 { return "Due today" }
        return "Next in \(days)d"
    }
}

struct PeriodTrackerToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeriodTrackerToolWidget", provider: PeriodProvider()) { entry in
            PeriodTrackerToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Period Tracker")
        .description("Tap flip to see your current cycle phase.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 5. Body Weight → current weight card

private let kWeightAccent = Color(hex: 0x2ECC71)

struct WeightEntryData: TimelineEntry {
    let date: Date
    let hasData: Bool
    let current: String
    let unit: String
    let change: String
    let flipped: Bool
}

struct WeightProvider: TimelineProvider {
    private let d = UserDefaults(suiteName: kWidgetAppGroup)
    private let wid = "tool_weight_tracker"

    func placeholder(in context: Context) -> WeightEntryData { load(flippedOverride: false) }
    func getSnapshot(in context: Context, completion: @escaping (WeightEntryData) -> Void) {
        completion(context.isPreview ? load(flippedOverride: false) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightEntryData>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 60, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load(flippedOverride: Bool? = nil) -> WeightEntryData {
        WeightEntryData(
            date: Date(),
            hasData: d?.bool(forKey: "weight_has_data") ?? false,
            current: d?.string(forKey: "weight_current") ?? "",
            unit: d?.string(forKey: "weight_unit") ?? "kg",
            change: d?.string(forKey: "weight_change") ?? "",
            flipped: flippedOverride ?? (d?.bool(forKey: "flipped_\(wid)") ?? false)
        )
    }
}

struct WeightTrackerToolWidgetView: View {
    var entry: WeightEntryData
    private let wid = "tool_weight_tracker"

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ToolFlipButton(widgetId: wid, kind: "WeightTrackerToolWidget", accent: kWeightAccent).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                WidgetThemeToggleButton(isDark: widgetThemeIsDark(wid), widgetId: wid).padding(6)
            }
            .modifier(LiveToolBackgroundModifier(accent: kWeightAccent, widgetId: wid))
            .widgetURL(URL(string: "aiwellnesspal://open?homeWidget=1&screen=tool_weight_tracker"))
    }

    @ViewBuilder private var content: some View {
        if entry.flipped {
            let hasData = entry.hasData && !entry.current.isEmpty
            VStack(spacing: 4) {
                Spacer().frame(height: 14)
                Text("⚖️").font(.system(size: 26))
                if hasData {
                    Text("CURRENT WEIGHT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(widgetTextColor(wid).opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(entry.current)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(kWeightAccent)
                        Text(entry.unit)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(kWeightAccent)
                    }
                    if !entry.change.isEmpty {
                        Text("\(entry.change) \(entry.unit)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(widgetTextColor(wid))
                    }
                } else {
                    Text("No weight logged")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(widgetTextColor(wid))
                    Text("Open app to sync")
                        .font(.system(size: 9))
                        .foregroundColor(widgetTextColor(wid).opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
        } else {
            ToolDefaultTile(emoji: "⚖️", label: "Body Weight", widgetId: wid)
        }
    }
}

struct WeightTrackerToolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightTrackerToolWidget", provider: WeightProvider()) { entry in
            WeightTrackerToolWidgetView(entry: entry)
        }
        .configurationDisplayName("Body Weight")
        .description("Tap flip to see your current weight.")
        .supportedFamilies([.systemSmall])
    }
}
