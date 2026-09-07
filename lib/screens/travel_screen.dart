import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/travel_memory.dart';
import '../providers/app_state.dart';
import '../services/achievement_service.dart';
import '../services/travel_wellness_service.dart';
import '../utils/pro_modal_utils.dart';
import '../utils/wellnesspal_snackbar.dart';
import 'achievement_completion_page.dart';

/// Mindful Travel — a Life Toolkit wellness tool.
///
/// Log trips with travel dates and personal notes. Each destination gets
/// AI-generated, location-aware wellness guidance (hydration, jet-lag,
/// movement, mindful presence). Active / upcoming trips also feed into the
/// AI daily wellness plan automatically.
///
/// No map. No public sharing. Just you and your travel wellness.
class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key});

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F3FB),
      appBar: _buildAppBar(theme),
      body: TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _tabController,
        children: const [
          _TripsTab(),
          _WellnessTab(),
        ],
      ),
    );
  }

  AppBar _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: const Text('Mindful Travel',
          style: TextStyle(fontWeight: FontWeight.bold)),
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'My Trips', icon: Icon(Icons.luggage_rounded, size: 18)),
          Tab(
            text: 'Wellness',
            icon: Icon(Icons.self_improvement_rounded, size: 18),
          ),
        ],
        labelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded),
          tooltip: 'Log a trip',
          onPressed: () => _showAddTripSheet(context),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Add / edit trip sheet — exposed so child widgets can call it.
  // ---------------------------------------------------------------------------

  void _showAddTripSheet(BuildContext context, {TravelMemory? existing}) {
    final appState = Provider.of<AppState>(context, listen: false);

    if (existing == null &&
        !appState.isPro &&
        appState.travelMemories.length >= 3) {
      ProModalUtils.showTravelLimitModal(context);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTripSheet(
        existing: existing,
        onSave: (place, note, startDate, endDate, {String? id}) async {
          if (existing != null) {
            final updated = TravelMemory(
              id: existing.id,
              place: place,
              latitude: existing.latitude,
              longitude: existing.longitude,
              visitedDate: existing.visitedDate,
              startDate: startDate,
              endDate: endDate,
              memory: '',
              note: note,
              photos: existing.photos,
              isPublic: false,
              wellnessGuidance: existing.wellnessGuidance,
            );
            await appState.updateTravelMemory(updated);
            if (mounted) {
              WellnessPalSnackBar.show(context,
                  message: 'Trip updated',
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green);
            }
          } else {
            WellnessPalSnackBar.show(context,
                message: 'Adding trip…', icon: Icons.sync);
            List<Achievement> achievements = [];
            try {
              achievements = await appState.addTravelMemory(
                place, 0.0, 0.0,
                id: id,
                memory: '',
                note: note,
                photos: const [],
                isPublic: false,
                startDate: startDate,
                endDate: endDate,
              );
              if (mounted) {
                WellnessPalSnackBar.show(context,
                    message: 'Trip logged!',
                    icon: Icons.check_circle,
                    iconColor: Colors.green);
              }
            } catch (e) {
              if (mounted) {
                WellnessPalSnackBar.show(context,
                    message: 'Could not add trip: $e', isError: true);
              }
              rethrow;
            }

            if (mounted && achievements.isNotEmpty) {
              Future.microtask(() async {
                for (final ach in achievements) {
                  if (!mounted) break;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        AchievementCompletionPage(achievement: ach),
                    fullscreenDialog: true,
                  ));
                  if (achievements.length > 1) {
                    await Future.delayed(const Duration(seconds: 2));
                  }
                }
              });
            }
          }
        },
      ),
    );
  }
}

// =============================================================================
// My Trips Tab
// =============================================================================

class _TripsTab extends StatelessWidget {
  const _TripsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, appState, _) {
      final all = appState.travelMemories.reversed.toList();
      if (all.isEmpty) return _emptyState(context);

      final active = all.where((m) => m.isActiveNow).toList();
      final upcoming =
          all.where((m) => m.isUpcoming && !m.isActiveNow).toList();
      final past =
          all.where((m) => !m.isActiveNow && !m.isUpcoming).toList();

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (active.isNotEmpty) ...[
            _sectionLabel(context, 'On this trip', Colors.green),
            const SizedBox(height: 8),
            ...active.map((m) => _TripCard(
                memory: m,
                onTap: () => _openDetail(context, m, appState))),
            const SizedBox(height: 20),
          ],
          if (upcoming.isNotEmpty) ...[
            _sectionLabel(context, 'Upcoming', Colors.orange),
            const SizedBox(height: 8),
            ...upcoming.map((m) => _TripCard(
                memory: m,
                onTap: () => _openDetail(context, m, appState))),
            const SizedBox(height: 20),
          ],
          if (past.isNotEmpty) ...[
            _sectionLabel(context, 'Past trips', null),
            const SizedBox(height: 8),
            ...past.map((m) => _TripCard(
                memory: m,
                onTap: () => _openDetail(context, m, appState))),
          ],
        ],
      );
    });
  }

  Widget _sectionLabel(BuildContext context, String label, Color? color) {
    final theme = Theme.of(context);
    return Text(label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: color ?? theme.colorScheme.onSurface.withOpacity(0.5),
          letterSpacing: 0.3,
        ));
  }

  void _openDetail(
      BuildContext context, TravelMemory m, AppState appState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TripDetailSheet(
        memory: m,
        onEdit: () {
          Navigator.pop(context);
          context
              .findAncestorStateOfType<_TravelScreenState>()
              ?._showAddTripSheet(context, existing: m);
        },
        onDelete: () async {
          Navigator.pop(context);
          final ok = await _confirmDelete(context);
          if (ok) {
            await appState.deleteTravelMemory(m.id);
            if (context.mounted) {
              WellnessPalSnackBar.show(context,
                  message: 'Trip removed',
                  icon: Icons.delete_forever);
            }
          }
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Remove trip?'),
              content: const Text(
                  'This will delete the trip and its wellness guidance.'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ) ??
          false;

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flight_takeoff_rounded,
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.25)),
            const SizedBox(height: 20),
            Text('No trips yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tap + to log your first trip.\nTravel is one of the best things you can do for your mind and wellbeing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color:
                      theme.colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Wellness Tab
// =============================================================================

class _WellnessTab extends StatefulWidget {
  const _WellnessTab();

  @override
  State<_WellnessTab> createState() => _WellnessTabState();
}

class _WellnessTabState extends State<_WellnessTab> {
  final _service = TravelWellnessService();
  final Map<String, bool> _loading = {};

  Future<void> _fetchGuidance(TravelMemory memory) async {
    if (_loading[memory.id] == true) return;
    setState(() => _loading[memory.id] = true);

    try {
      final ctx = TravelWellnessContext(
        place: memory.place,
        note: memory.note,
        isActiveNow: memory.isActiveNow,
        daysRemaining: memory.endDate != null
            ? memory.endDate!
                .difference(DateTime.now())
                .inDays
                .clamp(0, 999)
            : null,
      );
      final guidance = await _service.getGuidance(ctx);
      if (mounted) {
        await context
            .read<AppState>()
            .updateTravelMemory(memory.withGuidance(guidance));
      }
    } catch (e) {
      debugPrint('❌ _WellnessTabState._fetchGuidance: $e');
    } finally {
      if (mounted) setState(() => _loading.remove(memory.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, appState, _) {
      final memories = [...appState.travelMemories]..sort((a, b) {
          int r(TravelMemory m) =>
              m.isActiveNow ? 0 : (m.isUpcoming ? 1 : 2);
          return r(a).compareTo(r(b));
        });

      if (memories.isEmpty) return _emptyState(context);

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _headerBanner(context),
          const SizedBox(height: 16),
          ...memories.map((m) => _WellnessCard(
                memory: m,
                isLoading: _loading[m.id] == true,
                onRefresh: () => _fetchGuidance(m),
              )),
        ],
      );
    });
  }

  Widget _headerBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A7BD5), Color(0xFF1A55A5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Travel Wellness',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'Personalised wellness tips for each destination — hydration, sleep rhythm, movement, and mindful presence.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.self_improvement_rounded,
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.25)),
            const SizedBox(height: 20),
            Text('Wellness guide awaits',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Log a trip and tap the sparkle button to get personalised wellness guidance for that destination.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color:
                      theme.colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Trip Card
// =============================================================================

class _TripCard extends StatelessWidget {
  final TravelMemory memory;
  final VoidCallback onTap;
  const _TripCard({required this.memory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color statusColor;
    String statusLabel;
    if (memory.isActiveNow) {
      statusColor = Colors.green;
      statusLabel = 'Active';
    } else if (memory.isUpcoming) {
      statusColor = Colors.orange;
      statusLabel = _daysUntil();
    } else {
      statusColor = theme.colorScheme.onSurface.withOpacity(0.3);
      statusLabel = 'Past';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2124) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: memory.isActiveNow
              ? Border.all(color: Colors.green.withOpacity(0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            // Status dot / icon.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.flight_takeoff_rounded,
                  color: statusColor, size: 22),
            ),
            const SizedBox(width: 14),
            // Text block.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(memory.place,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  if (memory.startDate != null && memory.endDate != null)
                    Text(
                      '${_fmt(memory.startDate!)} – ${_fmt(memory.endDate!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5)),
                    )
                  else if (memory.startDate != null)
                    Text(_fmt(memory.startDate!),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.5))),
                  if (memory.note != null &&
                      memory.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      memory.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.45)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status badge.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _daysUntil() {
    if (memory.startDate == null) return 'Upcoming';
    final days =
        memory.startDate!.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Tomorrow';
    if (days == 1) return '1 day';
    return '$days days';
  }
}

// =============================================================================
// Wellness Card
// =============================================================================

class _WellnessCard extends StatelessWidget {
  final TravelMemory memory;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _WellnessCard({
    required this.memory,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasGuidance = memory.wellnessGuidance?.trim().isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2124) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header.
          Row(
            children: [
              Icon(Icons.place_rounded,
                  color: const Color(0xFF3A7BD5), size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(memory.place,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (memory.isActiveNow)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Active',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              // Guidance action button.
              SizedBox(
                width: 34,
                height: 34,
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          hasGuidance
                              ? Icons.refresh_rounded
                              : Icons.auto_awesome_rounded,
                          size: 18,
                          color: const Color(0xFF3A7BD5),
                        ),
                        tooltip: hasGuidance
                            ? 'Refresh guidance'
                            : 'Get wellness guidance',
                        onPressed: onRefresh,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Guidance body.
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Getting your personalised guidance…',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else if (hasGuidance)
            Text(memory.wellnessGuidance!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(height: 1.55,
                        color: theme.colorScheme.onSurface
                            .withOpacity(0.8)))
          else
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A7BD5).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF3A7BD5).withOpacity(0.18)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 15, color: Color(0xFF3A7BD5)),
                    SizedBox(width: 8),
                    Text('Tap to get AI wellness guidance',
                        style: TextStyle(
                            color: Color(0xFF3A7BD5),
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Trip Detail Bottom Sheet
// =============================================================================

class _TripDetailSheet extends StatelessWidget {
  final TravelMemory memory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TripDetailSheet({
    required this.memory,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.88,
      minChildSize: 0.35,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Title.
            Text(memory.place,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // Dates.
            if (memory.startDate != null && memory.endDate != null)
              _row(context, Icons.date_range_rounded,
                  '${_fmt(memory.startDate!)} – ${_fmt(memory.endDate!)}'),
            // Notes.
            if (memory.note != null && memory.note!.trim().isNotEmpty)
              _row(context, Icons.notes_rounded, memory.note!),
            // Wellness guidance.
            if (memory.wellnessGuidance?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A7BD5).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 14, color: Color(0xFF3A7BD5)),
                        SizedBox(width: 6),
                        Text('Wellness Guidance',
                            style: TextStyle(
                                color: Color(0xFF3A7BD5),
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(memory.wellnessGuidance!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(height: 1.5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Actions.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: Colors.red),
                    label: const Text('Remove',
                        style: TextStyle(color: Colors.red)),
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 16,
              color: theme.colorScheme.onSurface.withOpacity(0.4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Add / Edit Trip Sheet
// =============================================================================

typedef _OnSave = Future<void> Function(
  String place,
  String note,
  DateTime? startDate,
  DateTime? endDate, {
  String? id,
});

class _AddTripSheet extends StatefulWidget {
  final TravelMemory? existing;
  final _OnSave onSave;
  const _AddTripSheet({this.existing, required this.onSave});

  @override
  State<_AddTripSheet> createState() => _AddTripSheetState();
}

class _AddTripSheetState extends State<_AddTripSheet> {
  final _placeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _placeCtrl.text = e.place;
      _noteCtrl.text = e.note ?? '';
      _startDate = e.startDate;
      _endDate = e.endDate;
    }
  }

  @override
  void dispose() {
    _placeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ??
            (_startDate?.add(const Duration(days: 7)) ?? now));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked.add(const Duration(days: 7));
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    final place = _placeCtrl.text.trim();
    if (place.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        place,
        _noteCtrl.text.trim(),
        _startDate,
        _endDate,
        id: widget.existing?.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        WellnessPalSnackBar.show(context,
            message: 'Could not save trip. Please try again.',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Text(isEdit ? 'Edit Trip' : 'Log a Trip',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Travel is great for your mind. Log it and get personalised wellness guidance.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withOpacity(0.5)),
              ),
              const SizedBox(height: 20),

              // Destination field.
              TextField(
                controller: _placeCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Destination',
                  hintText: 'City, country, or landmark',
                  prefixIcon: const Icon(Icons.flight_takeoff_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  filled: true,
                ),
              ),

              const SizedBox(height: 16),

              // Travel dates.
              Text('Travel dates (optional)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: _startDate != null
                          ? _fmt(_startDate!)
                          : 'Departure',
                      icon: Icons.flight_takeoff_rounded,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: _endDate != null ? _fmt(_endDate!) : 'Return',
                      icon: Icons.flight_land_rounded,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Notes.
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText:
                      'What are you looking forward to? Any wellness goals for this trip?',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  filled: true,
                ),
              ),

              const SizedBox(height: 24),

              // Save button.
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(isEdit ? 'Save changes' : 'Log trip',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Date picker button widget
// =============================================================================

class _DateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(14),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF3A7BD5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File-level date formatter
// ---------------------------------------------------------------------------

String _fmt(DateTime d) => DateFormat('d MMM yyyy').format(d);
