import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/app_state.dart';
import '../../../utils/pro_modal_utils.dart';
import '../../../widgets/add_to_home_wrapper.dart';
import '../../../services/home_tool_cards_service.dart';
import '../../meal_planner/presentation/meal_planner_state.dart';
import '../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../weather/domain/weather_models.dart';
import '../../weather/presentation/location_setup_screen.dart';
import '../../weather/presentation/widgets/weather_card.dart';
import '../data/hydration_repository.dart';
import '../domain/hydration_models.dart';
import 'hydration_state.dart';
import 'widgets/hydration_cards.dart';

/// The AI Hydration Coach: water-fill dashboard, quick logging, AI insights,
/// reminders, timeline, weekly trend, score, and streak. The daily goal is
/// derived from the Meal Planner profile plus weather/exercise adjustments.
class HydrationCoachScreen extends StatefulWidget {
  const HydrationCoachScreen({super.key});

  @override
  State<HydrationCoachScreen> createState() => _HydrationCoachScreenState();
}

class _HydrationCoachScreenState extends State<HydrationCoachScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final state = context.read<HydrationState>();
    final planner = context.read<MealPlannerState>();
    await Future.wait([planner.load(), state.load()]);
    await state.syncProfile(planner.profile);
    await state.refreshAnalysis();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<HydrationState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFF0F8FE),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Hydration Coach'),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Weather location',
                icon: const Icon(Icons.wb_sunny_rounded),
                onPressed: () => _openLocationFlow(context, state),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => state.refreshAnalysis(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      _buildWeatherSection(context, state),
                      AddToHomeWrapper(
                        toolCardId: HomeToolCard.hydration,
                        child: HydrationProgressCard(
                          goalMl: state.goalMl,
                          consumedMl: state.consumedMl,
                          isManualGoal: state.isManualTarget,
                          onEditGoal: () => _showEditTarget(context, state),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildQuickAdd(context, state),
                      const SizedBox(height: 16),
                      SmartInsightsCard(
                        prediction: state.prediction,
                        insights: state.insights,
                        reminders: state.reminders,
                        isAnalyzing: state.isAnalyzing,
                      ),
                      const SizedBox(height: 16),
                      HydrationScoreCard(score: state.score),
                      const SizedBox(height: 16),
                      HydrationStreakCard(
                        currentStreak: state.currentStreak,
                        bestStreak: state.bestStreak,
                      ),
                      const SizedBox(height: 16),
                      HydrationTimelineCard(
                        entries: state.timeline,
                        onTapEntry: (e) => _confirmDelete(context, state, e),
                      ),
                      const SizedBox(height: 16),
                      WeeklyAnalyticsCard(points: _trendPoints(state)),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Top-of-dashboard weather section: real weather card when available, a
  /// Premium "set up weather" prompt when not, or a standard-target notice.
  Widget _buildWeatherSection(BuildContext context, HydrationState state) {
    final theme = Theme.of(context);

    // Live/cached weather → full card.
    if (state.weatherData != null && state.weatherLocation != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: WeatherCard(
          weather: state.weatherData!,
          location: state.weatherLocation!,
          adjustment: state.weatherAdjustment,
          stale: state.weatherStale,
          onChangeLocation: () => _openLocationFlow(context, state),
        ),
      );
    }

    // Location set but weather unavailable → friendly notice.
    if (state.weatherLocation != null && state.weatherError != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 20, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(state.weatherError!,
                  style: theme.textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => state.refreshWeather(force: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // No location yet → Premium set-up prompt.
    return GestureDetector(
      onTap: () => _openLocationFlow(context, state),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kHydrationAccent.withOpacity(0.16),
              kHydrationAccent.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kHydrationAccent.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_rounded,
                color: kHydrationAccent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Weather-aware hydration',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium_rounded,
                          size: 14, color: kHydrationAccent),
                    ],
                  ),
                  Text('Set your location to adjust your goal for the weather.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kHydrationAccent),
          ],
        ),
      ),
    );
  }

  /// Premium-gated Open-Meteo location setup / change flow.
  Future<void> _openLocationFlow(
      BuildContext context, HydrationState state) async {
    final appState = context.read<AppState>();
    if (!appState.isPro) {
      ProModalUtils.showProStatusModal(context, false);
      return;
    }
    final nationality = context.read<MealPlannerState>().profile?.nationality;
    final result = await Navigator.of(context).push<WeatherLocation>(
      MaterialPageRoute(
        builder: (_) =>
            LocationSetupScreen(defaultCountryName: nationality),
      ),
    );
    if (result != null) {
      // Save → refresh weather → recalculate goal (handled in state).
      await state.setWeatherLocation(result);
      await state.refreshAnalysis();
    }
  }

  // ---------------------------------------------------------------------------
  // Quick add
  // ---------------------------------------------------------------------------
  Widget _buildQuickAdd(BuildContext context, HydrationState state) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick add',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...HydrationState.quickAddOptions.map((ml) => _addChip(
                    context,
                    formatMl(ml),
                    () => state.logWater(ml),
                  )),
              _addChip(context, 'Custom', () => _showCustom(context, state),
                  outlined: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addChip(BuildContext context, String label, VoidCallback onTap,
      {bool outlined = false}) {
    return Material(
      color: outlined ? Colors.transparent : kHydrationAccent.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: kHydrationAccent.withOpacity(outlined ? 0.5 : 0.25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: kHydrationAccent),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: kHydrationAccent)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustom(BuildContext context, HydrationState state) {
    final c = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _Sheet(
          title: 'Custom amount',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  suffixText: 'ml',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kHydrationAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final ml = int.tryParse(c.text.trim()) ?? 0;
                  if (ml > 0) state.logWater(ml, source: 'manual');
                  Navigator.pop(ctx);
                },
                child: const Text('Add water'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Edit the daily base water target (or reset it to the auto-calculated one).
  void _showEditTarget(BuildContext context, HydrationState state) {
    final c = TextEditingController(text: state.baseTargetMl.toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _Sheet(
          title: 'Daily water target',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Set your base daily target. Exercise and weather adjustments '
                'are still added on top.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Target',
                  suffixText: 'ml',
                  helperText:
                      '${HydrationState.minTargetMl}–${HydrationState.maxTargetMl} ml',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kHydrationAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final ml = int.tryParse(c.text.trim()) ?? 0;
                  if (ml > 0) {
                    state.setManualTarget(ml);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save target'),
              ),
              if (state.isManualTarget) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    state.setManualTarget(null);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Reset to automatic'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, HydrationState state, HydrationEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Sheet(
        title: 'Remove entry',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Remove ${formatMl(e.amountMl)} logged at '
                '${_time(e.timestamp)}?'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE9506E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.delete_rounded),
              label: const Text('Remove'),
              onPressed: () {
                state.removeEntry(e.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  List<HydrationTrendPoint> _trendPoints(HydrationState state) {
    final recent = state.recent.reversed.take(7).toList();
    final points = recent
        .map((d) => HydrationTrendPoint(
              date: DateTime.tryParse(d.date) ?? DateTime.now(),
              consumedMl: d.consumedMl,
              goalMl: d.goalMl,
            ))
        .toList();
    final todayKey = HydrationRepository.dateKey(DateTime.now());
    if (!recent.any((d) => d.date == todayKey)) {
      points.add(HydrationTrendPoint(
        date: DateTime.now(),
        consumedMl: state.consumedMl,
        goalMl: state.goalMl,
      ));
    }
    if (points.length > 7) return points.sublist(points.length - 7);
    return points;
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

/// Rounded bottom-sheet with grab handle + title (module-local).
class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _Sheet({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        child,
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(child: content),
    );
  }
}
