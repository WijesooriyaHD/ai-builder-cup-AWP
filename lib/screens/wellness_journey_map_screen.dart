import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:provider/provider.dart';

import '../models/check_in.dart';
import '../models/daily_plan.dart';
import '../models/travel_memory.dart';
import '../models/wellness_enums.dart';
import '../models/wellness_milestone.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../widgets/frosted_container.dart';

/// Wellness Journey Map Screen — replaces the Travel Map with a visual timeline
/// showing milestones achieved at plan counts 1, 5, 10, 25, 50.
///
/// Primary path: Mapbox PolylineAnnotationManager (timeline spine) +
/// PointAnnotationManager (milestone markers).
/// Fallback path: Flutter CustomPainter timeline (if Mapbox fails to init).
class WellnessJourneyMapScreen extends StatefulWidget {
  const WellnessJourneyMapScreen({super.key});

  @override
  State<WellnessJourneyMapScreen> createState() =>
      _WellnessJourneyMapScreenState();
}

class _WellnessJourneyMapScreenState extends State<WellnessJourneyMapScreen> {
  static const String _accessToken =
      "YOUR_MAPBOX_ACCESS_TOKEN";

  bool _mapboxInitialized = false;
  bool _mapboxFailed = false;
  PolylineAnnotationManager? _polylineManager;
  PointAnnotationManager? _pointManager;
  final Map<String, TravelMemory> _milestoneMarkerMap = {};

  /// Currently selected milestone for detail card display.
  TravelMemory? _selectedMilestone;

  /// Tracks milestone IDs we've already seen, so newly created ones animate in.
  Set<String> _previousMilestoneIds = {};

  @override
  void initState() {
    super.initState();
    _initMapbox();
  }

  Future<void> _initMapbox() async {
    try {
      MapboxOptions.setAccessToken(_accessToken);
      // If setAccessToken succeeds without error we consider Mapbox available.
      // Actual map creation happens in the widget tree via MapWidget's onMapCreated.
      if (mounted) {
        setState(() {
          _mapboxInitialized = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mapboxFailed = true;
        });
      }
    }
  }

  List<TravelMemory> _getMilestones(AppState appState) {
    // Milestones are stored as TravelMemory entries where latitude stores the
    // MilestoneType ordinal. Filter to those with valid milestone type ordinals.
    return appState.travelMemories.where((m) {
      final typeIndex = m.latitude.round();
      return typeIndex >= 0 && typeIndex < MilestoneType.values.length;
    }).toList()
      ..sort((a, b) => a.longitude.compareTo(b.longitude)); // Sort by plan count
  }

  MilestoneType _milestoneTypeFrom(TravelMemory memory) {
    final index = memory.latitude.round().clamp(0, MilestoneType.values.length - 1);
    return MilestoneType.values[index];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wellness Journey'),
        centerTitle: true,
      ),
      body: Consumer3<AppState, WellnessPlanState, CheckInState>(
        builder: (context, appState, planState, checkInState, _) {
          final milestones = _getMilestones(appState);

          // Track milestone IDs for animated appearance detection
          final currentIds = milestones.map((m) => m.id).toSet();
          final newMilestoneIds =
              currentIds.difference(_previousMilestoneIds);
          _previousMilestoneIds = currentIds;

          // Empty state: no completed plans / no milestones
          if (milestones.isEmpty) {
            return _buildEmptyState(context);
          }

          // Build the full journey view with data layers
          return _buildJourneyContent(
            context,
            milestones: milestones,
            recentPlans: planState.recentPlans,
            recentCheckIns: checkInState.recentCheckIns,
            newMilestoneIds: newMilestoneIds,
          );
        },
      ),
    );
  }

  /// Builds the full journey content with timeline and data layers.
  Widget _buildJourneyContent(
    BuildContext context, {
    required List<TravelMemory> milestones,
    required List<DailyPlan> recentPlans,
    required List<CheckIn> recentCheckIns,
    required Set<String> newMilestoneIds,
  }) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          children: [
            // 7-Day Trend Badge
            _buildSevenDayTrendBadge(context, recentPlans),
            const SizedBox(height: 16),

            // Energy Trend Line
            _buildEnergyTrendLine(context, recentCheckIns),
            const SizedBox(height: 16),

            // Recovery Achievements
            _buildRecoveryAchievements(context, recentPlans, recentCheckIns),
            const SizedBox(height: 16),

            // Timeline section header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Milestones',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),

            // Timeline (fallback or Mapbox inline)
            if (_mapboxFailed || !_mapboxInitialized)
              _buildInlineFallbackTimeline(context, milestones, newMilestoneIds)
            else
              SizedBox(
                height: 400,
                child: _buildMapboxTimeline(context, milestones),
              ),
          ],
        ),
        if (_selectedMilestone != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: _buildMilestoneDetailCard(context, _selectedMilestone!),
          ),
      ],
    );
  }

  // ─── Empty State ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline_rounded,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Wellness Journey',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Complete your first plan to begin your journey',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.textTheme.bodyLarge?.color?.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 7-Day Trend Badge ────────────────────────────────────────────────────────

  /// Builds a badge showing the count of completed plans in the last 7 days
  /// and a directional arrow comparing to the previous 7 days.
  Widget _buildSevenDayTrendBadge(
      BuildContext context, List<DailyPlan> recentPlans) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));

    final currentWeekCompleted = recentPlans.where((p) =>
        p.isCompleted && p.date.isAfter(sevenDaysAgo)).length;

    final previousWeekCompleted = recentPlans.where((p) =>
        p.isCompleted &&
        p.date.isAfter(fourteenDaysAgo) &&
        p.date.isBefore(sevenDaysAgo)).length;

    final isUp = currentWeekCompleted >= previousWeekCompleted;
    final arrow = isUp ? '↑' : '↓';
    final arrowColor = isUp ? Colors.green : Colors.orange;
    final theme = Theme.of(context);

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.trending_up_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '7-Day Trend',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currentWeekCompleted plan${currentWeekCompleted == 1 ? '' : 's'} completed this week',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: arrowColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$currentWeekCompleted',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: arrowColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    arrow,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: arrowColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Energy Trend Line ──────────────────────────────────────────────────────

  /// Builds an energy trend line chart with one data point per check-in day
  /// for the last 30 days. If fewer than 30 days are available, shows all
  /// available points with the actual date range label.
  Widget _buildEnergyTrendLine(
      BuildContext context, List<CheckIn> recentCheckIns) {
    // Filter check-ins that have energy scores, limited to last 30 days
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final energyCheckIns = recentCheckIns
        .where((c) => c.energyScore != null && c.date.isAfter(thirtyDaysAgo))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final theme = Theme.of(context);

    // Date range label
    String dateRangeLabel;
    if (energyCheckIns.isEmpty) {
      dateRangeLabel = 'No energy data yet';
    } else if (energyCheckIns.length < 30) {
      final start = _formatShortDate(energyCheckIns.first.date);
      final end = _formatShortDate(energyCheckIns.last.date);
      dateRangeLabel = '$start – $end (${energyCheckIns.length} day${energyCheckIns.length == 1 ? '' : 's'})';
    } else {
      dateRangeLabel = 'Last 30 days';
    }

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Energy Trend',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  dateRangeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (energyCheckIns.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Complete check-ins to see your energy trend',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 100,
                child: CustomPaint(
                  size: const Size(double.infinity, 100),
                  painter: _EnergyTrendPainter(
                    energyScores: energyCheckIns
                        .map((c) => c.energyScore!)
                        .toList(),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Recovery Achievements ──────────────────────────────────────────────────

  /// Displays completed plans where the associated check-in had
  /// recoveryStatus of wellRested or recovering.
  Widget _buildRecoveryAchievements(
    BuildContext context,
    List<DailyPlan> recentPlans,
    List<CheckIn> recentCheckIns,
  ) {
    // Build a map of check-in IDs to recovery status
    final checkInRecoveryMap = <String, RecoveryStatus>{};
    for (final checkIn in recentCheckIns) {
      if (checkIn.recoveryStatus != null) {
        checkInRecoveryMap[checkIn.id] = checkIn.recoveryStatus!;
      }
    }

    // Find completed plans with qualifying recovery status
    final recoveryPlans = recentPlans.where((plan) {
      if (!plan.isCompleted || plan.checkInId == null) return false;
      final status = checkInRecoveryMap[plan.checkInId];
      return status == RecoveryStatus.wellRested ||
          status == RecoveryStatus.recovering;
    }).toList();

    final theme = Theme.of(context);

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.spa_rounded,
                  color: theme.colorScheme.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recovery Achievements',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${recoveryPlans.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recoveryPlans.isEmpty)
              Text(
                'Complete plans on well-rested or recovering days to earn recovery achievements',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
              )
            else
              ...recoveryPlans.take(5).map((plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.todaysFocus,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatShortDate(plan.date),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  // ─── Inline Fallback Timeline (with animated milestone appearance) ──────────

  Widget _buildInlineFallbackTimeline(
    BuildContext context,
    List<TravelMemory> milestones,
    Set<String> newMilestoneIds,
  ) {
    return CustomPaint(
      painter: _TimelineSpinePainter(
        milestoneCount: milestones.length,
        color: Theme.of(context).colorScheme.primary,
      ),
      child: Column(
        children: [
          for (var i = 0; i < milestones.length; i++)
            _buildAnimatedMilestoneRow(
              context,
              milestones[i],
              i,
              isNew: newMilestoneIds.contains(milestones[i].id),
            ),
        ],
      ),
    );
  }

  /// Builds a milestone row with animated appearance when it's newly created.
  /// New milestones animate in within 1500ms using flutter_animate.
  Widget _buildAnimatedMilestoneRow(
    BuildContext context,
    TravelMemory milestone,
    int index, {
    required bool isNew,
  }) {
    final row = _buildFallbackMilestoneRow(context, milestone, index);

    if (isNew) {
      return row
          .animate()
          .fadeIn(duration: 1500.ms, curve: Curves.easeOut)
          .slideY(begin: 0.3, end: 0, duration: 1500.ms, curve: Curves.easeOut)
          .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 1500.ms, curve: Curves.easeOut);
    }

    return row;
  }

  String _formatShortDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  // ─── Mapbox Timeline (Primary Path) ─────────────────────────────────────────

  Widget _buildMapboxTimeline(BuildContext context, List<TravelMemory> milestones) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: MapWidget(
        key: const ValueKey('wellness_journey_map'),
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(0, 0)),
          zoom: 1.0,
        ),
        styleUri: MapboxStyles.LIGHT,
        onMapCreated: (map) => _onMapCreated(map, milestones),
      ),
    );
  }

  Future<void> _onMapCreated(
      MapboxMap mapboxMap, List<TravelMemory> milestones) async {
    try {
      // Create annotation managers
      _polylineManager =
          await mapboxMap.annotations.createPolylineAnnotationManager();
      _pointManager =
          await mapboxMap.annotations.createPointAnnotationManager();

      // Add click listener for milestone markers
      _pointManager?.addOnPointAnnotationClickListener(
        _MilestoneClickListener(this),
      );

      // Draw the timeline spine as a vertical polyline
      await _drawTimelineSpine(milestones);

      // Draw milestone markers
      await _drawMilestoneMarkers(milestones);
    } catch (_) {
      // If Mapbox annotation setup fails, switch to fallback
      if (mounted) {
        setState(() {
          _mapboxFailed = true;
        });
      }
    }
  }

  Future<void> _drawTimelineSpine(List<TravelMemory> milestones) async {
    if (_polylineManager == null || milestones.isEmpty) return;

    // Create a vertical line of coordinates representing the timeline
    final points = <Point>[];
    for (var i = 0; i < milestones.length; i++) {
      // Space milestones vertically along a longitude line
      final lat = 60.0 - (i * (120.0 / (milestones.length.clamp(2, 50) - 1)));
      points.add(Point(coordinates: Position(0, lat)));
    }

    if (points.length < 2) {
      // Need at least 2 points for a polyline; duplicate if single milestone
      points.add(Point(coordinates: Position(0, points.first.coordinates.lat - 20)));
    }

    final polylineOptions = PolylineAnnotationOptions(
      geometry: LineString(coordinates: points.map((p) => p.coordinates).toList()),
      lineColor: Theme.of(context).colorScheme.primary.value,
      lineWidth: 4.0,
      lineOpacity: 0.7,
    );

    await _polylineManager?.create(polylineOptions);
  }

  Future<void> _drawMilestoneMarkers(List<TravelMemory> milestones) async {
    if (_pointManager == null) return;

    _milestoneMarkerMap.clear();

    final annotationOptions = <PointAnnotationOptions>[];
    for (var i = 0; i < milestones.length; i++) {
      final lat = 60.0 - (i * (120.0 / (milestones.length.clamp(2, 50) - 1)));
      annotationOptions.add(PointAnnotationOptions(
        geometry: Point(coordinates: Position(0, lat)),
        iconSize: 1.5,
        iconColor: Theme.of(context).colorScheme.primary.value,
      ));
    }

    final annotations = await _pointManager?.createMulti(annotationOptions);
    if (annotations != null) {
      for (var i = 0; i < annotations.length; i++) {
        final annotation = annotations[i];
        if (annotation != null && i < milestones.length) {
          _milestoneMarkerMap[annotation.id] = milestones[i];
        }
      }
    }
  }

  void _onMilestoneMarkerTap(PointAnnotation annotation) {
    final milestone = _milestoneMarkerMap[annotation.id];
    if (milestone != null && mounted) {
      setState(() {
        _selectedMilestone = milestone;
      });
    }
  }

  // ─── Fallback Timeline Row (CustomPainter) ───────────────────────────────────

  Widget _buildFallbackMilestoneRow(
      BuildContext context, TravelMemory milestone, int index) {
    final planCount = milestone.longitude.round();
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMilestone = milestone;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 40, bottom: 24),
        child: Row(
          children: [
            // Circle marker
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  width: 3,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FrostedContainer(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone.place,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$planCount plan${planCount == 1 ? '' : 's'} completed',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(milestone.visitedDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Milestone Detail Card ──────────────────────────────────────────────────

  Widget _buildMilestoneDetailCard(BuildContext context, TravelMemory milestone) {
    final type = _milestoneTypeFrom(milestone);
    final theme = Theme.of(context);
    final supportingMessage = WellnessMilestoneHelper.supportingMessageFor(type);

    return GestureDetector(
      onTap: () {
        // Dismiss card on tap
        setState(() {
          _selectedMilestone = null;
        });
      },
      child: FrostedContainer(
        blur: 20,
        opacity: 0.2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      milestone.place,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedMilestone = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _formatDate(milestone.visitedDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                supportingMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// ─── Mapbox Milestone Click Listener ──────────────────────────────────────────

class _MilestoneClickListener extends OnPointAnnotationClickListener {
  final _WellnessJourneyMapScreenState _state;

  _MilestoneClickListener(this._state);

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    _state._onMilestoneMarkerTap(annotation);
  }
}

// ─── CustomPainter for Fallback Timeline Spine ────────────────────────────────

class _TimelineSpinePainter extends CustomPainter {
  final int milestoneCount;
  final Color color;

  _TimelineSpinePainter({
    required this.milestoneCount,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (milestoneCount == 0) return;

    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw the vertical spine line on the left side
    const leftOffset = 50.0; // Aligns with the circle markers
    final topY = 10.0;
    final bottomY = size.height - 10.0;

    canvas.drawLine(
      Offset(leftOffset, topY),
      Offset(leftOffset, bottomY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineSpinePainter oldDelegate) {
    return oldDelegate.milestoneCount != milestoneCount ||
        oldDelegate.color != color;
  }
}

// ─── CustomPainter for Energy Trend Line ──────────────────────────────────────

class _EnergyTrendPainter extends CustomPainter {
  final List<int> energyScores;
  final Color color;

  _EnergyTrendPainter({
    required this.energyScores,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (energyScores.isEmpty) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Padding for dots at edges
    const horizontalPadding = 8.0;
    const verticalPadding = 8.0;
    final drawWidth = size.width - horizontalPadding * 2;
    final drawHeight = size.height - verticalPadding * 2;

    // Map scores (1-5) to y coordinates (inverted: 5 = top, 1 = bottom)
    final points = <Offset>[];
    for (var i = 0; i < energyScores.length; i++) {
      final x = energyScores.length == 1
          ? size.width / 2
          : horizontalPadding + (i / (energyScores.length - 1)) * drawWidth;
      final normalizedY = (energyScores[i] - 1) / 4.0; // 0.0 to 1.0
      final y = verticalPadding + drawHeight * (1.0 - normalizedY);
      points.add(Offset(x, y));
    }

    if (points.length == 1) {
      // Single point: just draw a dot
      canvas.drawCircle(points.first, 4, dotPaint);
      return;
    }

    // Draw filled area below the line
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw the line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Draw dots at each data point
    for (final point in points) {
      canvas.drawCircle(point, 3, dotPaint);
    }

    // Draw horizontal reference lines (at score 1 and 5)
    final refPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Line at score 5 (top)
    canvas.drawLine(
      Offset(horizontalPadding, verticalPadding),
      Offset(size.width - horizontalPadding, verticalPadding),
      refPaint,
    );
    // Line at score 1 (bottom)
    canvas.drawLine(
      Offset(horizontalPadding, size.height - verticalPadding),
      Offset(size.width - horizontalPadding, size.height - verticalPadding),
      refPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EnergyTrendPainter oldDelegate) {
    return oldDelegate.energyScores != energyScores ||
        oldDelegate.color != color;
  }
}
