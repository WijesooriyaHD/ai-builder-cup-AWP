import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:aiwellnesspal/utils/wellnesspal_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/wellness_enums.dart';
import '../models/journal_entry.dart';
import '../models/wellness_method.dart';
import '../providers/app_state.dart';
import '../providers/wellness_plan_state.dart';
import '../providers/check_in_state.dart';
import 'add_journal_entry_screen.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/storage_service.dart';
import '../services/toolkit_context_builder.dart';
import '../widgets/ai_wellness_insight_card.dart';
import '../widgets/custom_tab_switcher.dart';
import '../widgets/daily_plan_card.dart';
import '../widgets/frosted_container.dart';
import '../widgets/offline_indicator_banner.dart';
import '../widgets/sync_error_banner.dart';
import '../widgets/wellness_loading_state.dart';
import '../utils/pro_modal_utils.dart';
import 'check_in_screen.dart';
import 'explore_tab_screen.dart';
import 'achievements_screen.dart';
import '../services/home_tool_cards_service.dart';
import '../widgets/home_tool_card_views.dart';
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/meal_planner/presentation/meal_planner_state.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/calorie_budget/presentation/calorie_budget_state.dart';

/// The Wellness Command Center — the primary home screen of AI Wellness Pal.
///
/// Displays sections in order:
/// 1. Personalized greeting (preferred name → first name fallback)
/// 2. Today's Wellness Focus
/// 3. Energy Score summary
/// 4. Recovery Status summary
/// 5. Daily Plan card with interactive action checkboxes
/// 6. AI Wellness Insight card (Premium)
///
/// (Wellness Studio was moved to the "More" tab — see ExploreTabScreen.)
///
/// Requirements: 4.1, 4.2, 4.3, 4.4, 4.7
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _syncErrorVisible = false;
  String? _displayName;
  bool _aiInsightsEnabled = true;

  /// SharedPreferences key for AI insights toggle.
  /// This key is written by the Settings screen (task 16.1).
  static const String _aiInsightsDisabledKey = 'wellness_ai_insights_disabled';

  // ---------------------------------------------------------------------------
  // Home card ordering (long-press: pin-to-top / re-arrange)
  // ---------------------------------------------------------------------------

  /// Stable identifiers for the reorderable Home cards. The greeting, studio
  /// recommendation, and pinned reflections are intentionally NOT reorderable,
  /// so they are not part of this set.
  static const String _cardWellnessFocus = 'wellness_focus';
  static const String _cardEnergyScore = 'energy_score';
  static const String _cardRecoveryStatus = 'recovery_status';
  static const String _cardAvailableTime = 'available_time';
  static const String _cardDailyPlan = 'daily_plan';
  static const String _cardAiInsight = 'ai_insight';

  /// The default (shipping) order of the reorderable cards.
  static const List<String> _defaultCardOrder = [
    _cardWellnessFocus,
    _cardEnergyScore,
    _cardRecoveryStatus,
    _cardAvailableTime,
    _cardDailyPlan,
    _cardAiInsight,
  ];

  /// SharedPreferences key storing the user's saved card order (comma-joined
  /// card ids). Persisted so the layout survives app/phone restarts.
  static const String _cardOrderKey = 'wellness_home_card_order';

  /// The current card order shown on Home. Starts as the default and is
  /// replaced by the persisted order (if any) in [_loadCardOrder].
  List<String> _cardOrder = List<String>.from(_defaultCardOrder);

  /// While true, the Home cards enter drag-and-drop re-arrange mode and a Save
  /// bar is shown. Set from the long-press menu; cleared on Save/cancel.
  bool _isRearranging = false;

  /// A working copy of the order edited during re-arrange mode. Committed to
  /// [_cardOrder] (and persisted) only when the user taps Save.
  List<String> _draftCardOrder = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
    _loadAiInsightsPreference();
    _loadCardOrder();
    _loadTodaysPlan();
    _checkAndPromptCheckIn();
    _tabController = TabController(length: 2, vsync: this);
    // Load the states behind any enabled Home tool cards so they show real
    // data even if the user hasn't opened those tool screens this session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEnabledToolData());
  }

  /// Loads the provider state behind each enabled wellness-tool Home card, so
  /// the embedded cards show live data on first Home render. Each state's
  /// load() is idempotent/safe to call; we only load what's actually shown.
  Future<void> _loadEnabledToolData() async {
    if (!mounted) return;
    final tools = context.read<HomeToolCardsService>();
    // Period & Body Weight read from AppState (already loaded app-wide), so
    // only the feature-module states need an explicit load here.
    if (tools.isEnabled(HomeToolCard.nutrition)) {
      unawaited(context.read<NutritionState>().load());
    }
    if (tools.isEnabled(HomeToolCard.mealPlanner)) {
      unawaited(context.read<MealPlannerState>().load());
    }
    if (tools.isEnabled(HomeToolCard.hydration)) {
      unawaited(context.read<HydrationState>().load());
    }
    if (tools.isEnabled(HomeToolCard.calorieBudget)) {
      unawaited(context.read<CalorieBudgetState>().load());
    }
  }

  /// Loads the saved Home card order. Any missing ids (e.g. a card added in a
  /// later app version) are appended in their default position, and unknown
  /// ids are dropped, so the list is always exactly the current card set.
  Future<void> _loadCardOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_cardOrderKey);
      if (raw == null || raw.isEmpty) return;
      final valid = _reconcileOrder(raw);
      if (mounted) {
        setState(() => _cardOrder = valid);
      } else {
        _cardOrder = valid;
      }
    } catch (e) {
      debugPrint('HomeScreen: failed to load card order: $e');
    }
  }

  /// Firestore field on the user doc mirroring [_cardOrder], so the Home layout
  /// follows the user across devices (not just this device's local cache).
  static const String _cardOrderField = 'home_card_order';

  /// Normalizes an arbitrary saved id list against the current card set:
  /// drops unknown ids and appends any missing ones in their default position.
  /// Guarantees the result is exactly the current cards, in a valid order.
  List<String> _reconcileOrder(List<String> saved) {
    // Keep default cards and any recognized wellness-tool cards; drop unknowns.
    final valid = saved
        .where((id) =>
            _defaultCardOrder.contains(id) || HomeToolCard.isToolCard(id))
        .toList();
    // Ensure every default card is present (forward-compat). Tool cards are
    // added via the enabled-set, so we don't force-append them here.
    for (final id in _defaultCardOrder) {
      if (!valid.contains(id)) valid.add(id);
    }
    return valid;
  }

  /// Persists [_cardOrder] so the arrangement survives a restart. Writes to the
  /// local cache (instant, offline-safe) AND mirrors to the user's Firestore
  /// profile doc so the layout syncs across devices.
  Future<void> _saveCardOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cardOrderKey, _cardOrder);
    } catch (e) {
      debugPrint('HomeScreen: failed to save card order locally: $e');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({_cardOrderField: _cardOrder}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('HomeScreen: failed to mirror card order to Firestore: $e');
      }
    }
  }

  /// Applies a card order fetched from Firestore (e.g. set on another device).
  /// Reconciled and only applied when it actually differs, to avoid needless
  /// rebuilds. Never overrides an in-progress re-arrange edit.
  void _applyCloudCardOrder(List<dynamic>? raw) {
    if (raw == null || _isRearranging || !mounted) return;
    final reconciled = _reconcileOrder(raw.map((e) => e.toString()).toList());
    if (_listEquals(reconciled, _cardOrder)) return;
    setState(() => _cardOrder = reconciled);
    // Keep the local cache in step with the cloud so a later offline launch
    // shows the same order.
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_cardOrderKey, reconciled))
        .catchError((_) => false);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Moves [cardId] to the very top of the Home cards and persists. Operates on
  /// the effective order so tool cards (which may not yet be in [_cardOrder])
  /// pin correctly; the resulting full order is saved.
  Future<void> _pinCardToTop(String cardId) async {
    final effective = _effectiveOrder();
    if (effective.isEmpty || effective.first == cardId) return;
    setState(() {
      _cardOrder = [
        cardId,
        ...effective.where((id) => id != cardId),
      ];
    });
    await _saveCardOrder();
  }

  /// Enters drag-and-drop re-arrange mode with a fresh working copy.
  void _enterRearrangeMode() {
    setState(() {
      // Only VISIBLE cards are draggable, so the re-arrange list matches
      // exactly what's on screen (no phantom cards). Includes enabled tool
      // cards via _effectiveOrder().
      _draftCardOrder = _visibleCardOrder(_effectiveOrder());
      _isRearranging = true;
    });
  }

  /// Commits the dragged order and leaves re-arrange mode, persisting.
  ///
  /// The draft contains only the visible cards. Any hidden cards (e.g. AI
  /// Insight for a non-Pro user) are re-appended in their previous relative
  /// order so the full [_cardOrder] stays complete and their position is
  /// preserved for when they become visible again.
  Future<void> _saveRearrange() async {
    // Preserve any currently-hidden cards (e.g. AI Insight when not applicable)
    // by re-appending them after the dragged, visible order.
    final effective = _effectiveOrder();
    final hidden =
        effective.where((id) => !_draftCardOrder.contains(id)).toList();
    setState(() {
      _cardOrder = [..._draftCardOrder, ...hidden];
      _isRearranging = false;
    });
    await _saveCardOrder();
  }

  /// Discards drag edits and leaves re-arrange mode.
  void _cancelRearrange() {
    setState(() => _isRearranging = false);
  }

  /// Builds the widget for a single reorderable card by its stable id.
  Widget _buildCardById(
    String id,
    WellnessPlanState planState,
    CheckInState checkInState,
  ) {
    switch (id) {
      case _cardWellnessFocus:
        return _buildWellnessFocusSection(context, planState);
      case _cardEnergyScore:
        return _buildEnergyScoreSection(context, checkInState);
      case _cardRecoveryStatus:
        return _buildRecoveryStatusSection(context, checkInState);
      case _cardAvailableTime:
        return _buildAvailableTimeSection(context, checkInState);
      case _cardDailyPlan:
        return _buildDailyPlanSection(context, planState);
      case _cardAiInsight:
        return Consumer<AppState>(
          builder: (context, appState, _) {
            final insight = planState.todaysPlan?.aiInsight;
            final hasInsight = insight != null && insight.trim().isNotEmpty;
            // When there's live insight text, show the real card. When there
            // isn't (but the feature applies), show a compact placeholder so
            // the card is still visible AND long-pressable for pin/re-arrange.
            if (hasInsight) {
              return AIWellnessInsightCard(
                aiInsight: insight,
                isPro: appState.isPro,
                insightsEnabled: _aiInsightsEnabled,
              );
            }
            return _buildAiInsightPlaceholder(context);
          },
        );
      default:
        // Wellness-tool cards the user added from a tool screen.
        if (HomeToolCard.isToolCard(id)) {
          return buildHomeToolCard(context, id) ?? const SizedBox.shrink();
        }
        return const SizedBox.shrink();
    }
  }

  /// A lightweight placeholder shown for the AI Insight card when there is no
  /// insight text yet. Keeps the card present (and therefore long-pressable for
  /// pin/re-arrange) instead of collapsing to nothing.
  Widget _buildAiInsightPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Wellness Insight',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your personalized insight will appear here after your '
                    'check-in.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
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

  /// A human-readable label for the long-press menu header.
  String _cardTitle(String id) {
    switch (id) {
      case _cardWellnessFocus:
        return "Today's Wellness Focus";
      case _cardEnergyScore:
        return 'Energy Score';
      case _cardRecoveryStatus:
        return 'Recovery Status';
      case _cardAvailableTime:
        return 'Available Time';
      case _cardDailyPlan:
        return 'Daily Plan';
      case _cardAiInsight:
        return 'AI Wellness Insight';
      default:
        if (HomeToolCard.isToolCard(id)) return HomeToolCard.titleFor(id);
        return 'Card';
    }
  }

  /// Whether [cardId] should currently be shown on Home. Only the AI Insight
  /// card is conditional — it applies to Pro users with insights enabled (and
  /// renders a placeholder when there's no insight text yet). This is the
  /// SINGLE source of truth for visibility, used by BOTH the normal render and
  /// the re-arrange list, so a hidden card never appears in only one of them.
  bool _isCardVisible(String cardId) {
    if (HomeToolCard.isToolCard(cardId)) {
      // A tool card is visible only while the user keeps it enabled on Home.
      return context.read<HomeToolCardsService>().isEnabled(cardId);
    }
    if (cardId != _cardAiInsight) return true;
    final isPro = Provider.of<AppState>(context, listen: false).isPro;
    return isPro && _aiInsightsEnabled;
  }

  /// The full ordered id list = the saved default-card order, then any enabled
  /// wellness-tool cards the user added (in the order stored in [_cardOrder] if
  /// present, else appended). This is what pin/re-arrange operate on.
  List<String> _effectiveOrder() {
    final enabled = context.read<HomeToolCardsService>().enabled.toSet();
    // Start from the saved order (which may already contain tool ids from a
    // previous pin/re-arrange), keeping only still-enabled tool ids.
    final result = <String>[];
    for (final id in _cardOrder) {
      if (HomeToolCard.isToolCard(id)) {
        if (enabled.contains(id)) result.add(id);
      } else {
        result.add(id);
      }
    }
    // Append any newly-enabled tool cards not yet in the saved order.
    for (final id in enabled) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  /// The effective order filtered to visible cards, preserving order.
  List<String> _visibleCardOrder(List<String> order) =>
      order.where(_isCardVisible).toList();

  /// Normal-mode card list: each card is long-pressable to open the
  /// pin-to-top / re-arrange menu. Uses [_visibleCardOrder] so it matches the
  /// re-arrange list exactly.
  List<Widget> _buildOrderedCards(
    BuildContext context,
    WellnessPlanState planState,
    CheckInState checkInState,
  ) {
    final widgets = <Widget>[];
    for (final id in _visibleCardOrder(_effectiveOrder())) {
      widgets.add(
        GestureDetector(
          // translucent (NOT opaque): several cards have their OWN inner
          // GestureDetector with onTap (energy/recovery/available-time edit,
          // studio navigate). An opaque wrapper would win the hit-test and the
          // inner tap detector — and, in the arena, could starve this
          // long-press. translucent lets both this long-press recognizer and
          // any inner tap recognizer enter the arena; a long hold wins here
          // while a quick tap still reaches the inner card. The AI Insight card
          // has no inner tap, so its long-press was only ever failing because
          // the wrapper wasn't reliably in the arena — this fixes that too.
          behavior: HitTestBehavior.translucent,
          onLongPress: () => _showCardOptions(context, id),
          child: _buildCardById(id, planState, checkInState),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }
    // Drop the trailing spacer so it doesn't double with the section below.
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
  }

  /// The long-press action sheet: Pin to top / Re-arrange.
  void _showCardOptions(BuildContext context, String cardId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? theme.cardColor : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _cardTitle(cardId),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.vertical_align_top_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('Pin to top'),
              enabled: _cardOrder.first != cardId,
              onTap: () {
                Navigator.pop(ctx);
                _pinCardToTop(cardId);
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_vert_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('Re-arrange'),
              onTap: () {
                Navigator.pop(ctx);
                _enterRearrangeMode();
              },
            ),
            // Wellness-tool cards were added from their tool screen, so they can
            // be taken back off Home from here too. Default Home cards are not
            // removable, so this option only shows for tool cards.
            if (HomeToolCard.isToolCard(cardId)) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              ListTile(
                leading: Icon(Icons.remove_circle_outline_rounded,
                    color: theme.colorScheme.error),
                title: Text(
                  'Remove from Home',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeToolCardFromHome(cardId);
                },
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// Removes a wellness-tool card from Home. The card stays available to re-add
  /// from its tool screen. Mirrors the "Add to Home" affordance on the tools.
  Future<void> _removeToolCardFromHome(String cardId) async {
    final tools = context.read<HomeToolCardsService>();
    await tools.remove(cardId);
    if (!mounted) return;
    WellnessPalSnackBar.show(
      context,
      message: '${HomeToolCard.titleFor(cardId)} removed from Home',
      icon: Icons.home_outlined,
    );
  }

  /// Re-arrange mode: a drag-and-drop list of card previews plus a Save/Cancel
  /// bar. Uses the draft order so edits are only committed on Save.
  Widget _buildRearrangeList(
    BuildContext context,
    WellnessPlanState planState,
    CheckInState checkInState,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header + Save / Cancel controls.
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_indicator_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag the cards to re-arrange, then Save.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary),
                ),
              ),
              TextButton(
                onPressed: _cancelRearrange,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _saveRearrange,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
        // The drag-and-drop list. shrinkWrap + non-scrollable physics so it
        // nests inside the outer SingleChildScrollView.
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _draftCardOrder.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final id = _draftCardOrder.removeAt(oldIndex);
              _draftCardOrder.insert(newIndex, id);
            });
          },
          itemBuilder: (context, index) {
            final id = _draftCardOrder[index];
            return _buildRearrangeTile(context, id, index, theme);
          },
        ),
      ],
    );
  }

  /// A single row in re-arrange mode: the card's name with a drag handle. We
  /// intentionally show a lightweight tile rather than the full card, so a long
  /// month/plan card doesn't make dragging unwieldy.
  Widget _buildRearrangeTile(
      BuildContext context, String id, int index, ThemeData theme) {
    return Container(
      key: ValueKey(id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _cardTitle(id),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_handle_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
        ],
      ),
    );
  }

  /// Listens for voice-pal requests to switch the Home/More sub-tab (e.g.
  /// "open Wellness Reads"). Held so we can detach in dispose().
  AppNavigationService? _navService;
  int _lastHomeSubTabRequestId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<AppNavigationService>();
    if (nav != _navService) {
      _navService?.removeListener(_onNavRequest);
      _navService = nav;
      _lastHomeSubTabRequestId = nav.homeSubTabRequestId;
      nav.addListener(_onNavRequest);
    }
  }

  /// Animates the inner switcher when a NEW sub-tab request arrives. Keyed off
  /// the request id so repeated requests for the same sub-tab still fire, and
  /// unrelated bottom-tab notifications are ignored.
  void _onNavRequest() {
    final nav = _navService;
    if (nav == null || !mounted) return;
    if (nav.homeSubTabRequestId == _lastHomeSubTabRequestId) return;
    _lastHomeSubTabRequestId = nav.homeSubTabRequestId;
    final target = nav.requestedHomeSubTab;
    if (target != _tabController.index) {
      _tabController.animateTo(target);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navService?.removeListener(_onNavRequest);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning to the app, reconcile any plan-action toggles the user
    // made on the home-screen widget (they're written to the shared cache
    // from a background isolate).
    if (state == AppLifecycleState.resumed && mounted) {
      Provider.of<WellnessPlanState>(context, listen: false)
          .reloadFromCache();
    }
  }

  /// Loads today's plan from cache/Firestore so it's available immediately
  /// on silent sign-in without requiring a pull-to-refresh.
  Future<void> _loadTodaysPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final wellnessPlanState =
        Provider.of<WellnessPlanState>(context, listen: false);
    await wellnessPlanState.loadTodaysPlan(user.uid);
  }

  /// Loads today's check-in status and prompts the user if they haven't
  /// checked in yet today. Presents CheckInScreen as a full-screen modal.
  /// Requirements: 2.1
  Future<void> _checkAndPromptCheckIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final checkInState = Provider.of<CheckInState>(context, listen: false);
    await checkInState.loadTodaysCheckIn(user.uid);

    if (!checkInState.hasCheckedInToday && mounted) {
      // Brief delay to let the home screen render first
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      // Re-check in case state changed during the delay
      if (!checkInState.hasCheckedInToday) {
        // Await the modal so we can guarantee a plan exists after it closes.
        await Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const CheckInScreen(),
          ),
        );
        if (mounted) {
          await _ensureTodaysPlan();
        }
      }
    } else {
      // Already checked in today (e.g. via another device/session) — make
      // sure a plan is present, generating a fallback if one is missing.
      await _ensureTodaysPlan();
    }
  }

  /// Guarantees today's plan is populated after a check-in.
  ///
  /// The check-in flow triggers generation fire-and-forget, and generation can
  /// fail or be skipped (e.g. the user dismissed the check-in). This reloads
  /// the plan and, if still missing but a check-in exists, generates one from
  /// that check-in so the home screen never gets stuck on the empty state.
  Future<void> _ensureTodaysPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final planState = Provider.of<WellnessPlanState>(context, listen: false);
    final checkInState = Provider.of<CheckInState>(context, listen: false);

    // First, try to load any plan already generated/persisted.
    await planState.loadTodaysPlan(user.uid);

    // If a plan exists or one is currently being generated, nothing to do.
    if (planState.todaysPlan != null || planState.isGenerating) return;

    // No plan yet — generate one from today's check-in if we have it.
    final checkIn = checkInState.todaysCheckIn;
    if (checkIn != null) {
      final appState = Provider.of<AppState>(context, listen: false);
      // Premium-only Life Toolkit context (null for Free users). Built
      // synchronously before the await so BuildContext isn't used across it.
      final premiumToolkitContext = ToolkitContextBuilder.build(context);
      await planState.generatePlan(
        user.uid,
        checkIn,
        intentions: appState.intentions,
        cycleContext: appState.cyclePhaseContext,
        travelContext: appState.travelContext,
        preferredMethods: appState.preferredMethods,
        premiumToolkitContext: premiumToolkitContext,
      );
    }
  }

  Future<void> _loadAiInsightsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final disabled = prefs.getBool(_aiInsightsDisabledKey) ?? false;
      if (mounted) {
        setState(() {
          _aiInsightsEnabled = !disabled;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Failed to load AI insights preference: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _displayName = data['display_name'] as String?;
        });
        // Mirror-in the cross-device Home card order (if the cloud has one).
        // We already have the doc, so this adds no extra read.
        _applyCloudCardOrder(data[_cardOrderField] as List<dynamic>?);
      }
    } catch (e) {
      debugPrint('HomeScreen: Failed to load user profile: $e');
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getDisplayName() {
    // Firestore display_name → auth display name → fallback
    if (_displayName != null && _displayName!.trim().isNotEmpty) {
      return _displayName!.trim();
    }
    final user = FirebaseAuth.instance.currentUser;
    final authName = user?.displayName;
    if (authName != null && authName.trim().isNotEmpty) {
      return authName.trim();
    }
    return user?.email?.split('@').first ?? 'there';
  }

  Future<void> _onRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final wellnessPlanState =
        Provider.of<WellnessPlanState>(context, listen: false);
    final checkInState = Provider.of<CheckInState>(context, listen: false);

    await Future.wait([
      wellnessPlanState.loadTodaysPlan(user.uid),
      checkInState.loadTodaysCheckIn(user.uid),
      _loadUserProfile(),
      _loadAiInsightsPreference(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 20,
        titleSpacing: 9,
        centerTitle: false,
        toolbarHeight: 70,
        title: Consumer<AppState>(
          builder: (context, appState, child) {
            return GestureDetector(
              onTap: () =>
                  ProModalUtils.showProStatusModal(context, appState.isPro),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo — left-aligned, sized by its intrinsic SVG width.
                  const _AnimatedGradientLogo(),
                  if (appState.isPro) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const SizedBox(width: 10),

                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B9D).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                size: 14,
                                color: Color(0xFFFF6B9D),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Premium',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF6B9D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTabSwitcher(
                tabController: _tabController,
                tabs: const ["Home", "More"],
                icons: const [Icons.home_rounded, Icons.unfold_more],
                width: 145,
                height: 40,
                isAppBarMode: true,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showUserProfileBottomSheet(context),
                child: StreamBuilder<User?>(
                    stream: AuthService().authStateChanges,
                    builder: (context, snapshot) {
                      final user = AuthService().currentUser;
                      final avatarUrl = user?.photoURL;

                      return Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: (avatarUrl == null || avatarUrl.isEmpty)
                              ? Icon(Icons.person_rounded, size: 20, color: Theme.of(context).primaryColor)
                              : null,
                        ),
                      );
                    }
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Tab content: Home (index 0) and Explore (index 1).
          // The CustomTabSwitcher in the AppBar drives _tabController, so
          // tapping "Explore" animates this view to the ExploreTabScreen.
          TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Home tab
              Consumer2<WellnessPlanState, CheckInState>(
                builder: (context, planState, checkInState, child) {
                  // Watch the tool-cards service so the Home layout updates the
                  // moment the user adds/removes a wellness-tool card.
                  context.watch<HomeToolCardsService>();
                  // Show loading state while plan is generating
                  if (planState.isGenerating) {
                    return const WellnessLoadingState();
                  }

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Personalized Greeting (fixed — not reorderable)
                          _buildGreetingSection(context),
                          const SizedBox(height: 24),

                          // Reorderable cards. In normal mode each card is
                          // long-pressable (pin-to-top / re-arrange). In
                          // re-arrange mode they become drag-and-drop with a
                          // Save bar.
                          if (_isRearranging)
                            _buildRearrangeList(context, planState, checkInState)
                          else
                            ..._buildOrderedCards(
                                context, planState, checkInState),

                          const SizedBox(height: 16),

                          // Reflections pinned to Home ("Add to Home") (fixed).
                          // (Wellness Studio now lives in the "More" tab.)
                          _buildPinnedJournalSection(context),

                          const SizedBox(height: 80),

                        ],
                      ),
                    ),
                  );
                },
              ),

              // Explore tab
              const ExploreTabScreen(),
            ],
          ),

          // Offline indicator banner (top of stack)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OfflineIndicatorBanner(
              connectivityService: _connectivityService,
              hasCachedData: Provider.of<WellnessPlanState>(context)
                      .todaysPlan !=
                  null,
            ),
          ),

          // Sync error banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SyncErrorBanner(
              isVisible: _syncErrorVisible,
              onDismiss: () => setState(() => _syncErrorVisible = false),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserProfileBottomSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // Allow keyboard to push sheet up
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const UserProfileSheet(),
      ),
    );
    // Refresh the Home screen to show updated profile data
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Section 8: Reflections pinned to Home
  // ---------------------------------------------------------------------------

  /// Renders the reflection entries the user pinned via "Add to Home".
  /// Returns an empty box when nothing is pinned.
  Widget _buildPinnedJournalSection(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pinned = appState.journalEntries
            .where((e) => appState.pinnedJournalToHomeIds.contains(e.id))
            .toList();
        if (pinned.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Pinned Reflections',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...pinned.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPinnedJournalCard(context, entry, appState),
                )),
          ],
        );
      },
    );
  }

  Widget _buildPinnedJournalCard(
      BuildContext context, JournalEntry entry, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Color(entry.color);
    final preview = entry.content.trim();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddJournalEntryScreen(entry: entry),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardColor : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border:
              Border.all(color: isDark ? Colors.white10 : Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color.lerp(accentColor, Colors.black, 0.2) ??
                        accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_stories_rounded,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.title.isNotEmpty ? entry.title : 'Reflection',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.mood != null) ...[
                  const SizedBox(width: 8),
                  Text(entry.mood!, style: const TextStyle(fontSize: 18)),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    appState.toggleJournalPinToHome(entry.id);
                    WellnessPalSnackBar.show(context,
                        message: 'Removed from Home',
                        icon: Icons.home_outlined);
                  },
                  child: Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey.withOpacity(0.5)),
                ),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1: Personalized Greeting
  // ---------------------------------------------------------------------------

  Widget _buildGreetingSection(BuildContext context) {
    final greeting = _getGreeting();
    final name = _getDisplayName();
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Achievement level indicator — taps through to the Achievements
        // screen. Uses the theme's primary color so it stays on-theme.
        _buildLevelBadge(context),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0);
  }

  /// Compact, tappable achievement-level badge shown to the right of the
  /// greeting. Navigates to the Achievements screen on tap.
  Widget _buildLevelBadge(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Consumer<AppState>(
      builder: (context, appState, _) {
        final level = appState.currentLevel;
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AchievementsScreen(),
              ),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary.withOpacity(0.18),
                  primary.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primary.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 16, color: primary),
                const SizedBox(width: 5),
                Text(
                  'Lv $level',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            // Subtle, slow shimmer to be eye-catching but not distracting.
            .shimmer(
              duration: 2200.ms,
              delay: 1200.ms,
              color: primary.withOpacity(0.35),
            );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2: Today's Wellness Focus
  // ---------------------------------------------------------------------------

  Widget _buildWellnessFocusSection(
      BuildContext context, WellnessPlanState planState) {
    final theme = Theme.of(context);
    final focus = planState.todaysPlan?.todaysFocus;

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.self_improvement_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  "Today's Wellness Focus",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              focus ?? 'Complete your check-in to set today\'s focus',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  // ---------------------------------------------------------------------------
  // Section 3: Energy Score Summary
  // ---------------------------------------------------------------------------

  Widget _buildEnergyScoreSection(
      BuildContext context, CheckInState checkInState) {
    final theme = Theme.of(context);
    final energyScore = checkInState.todaysCheckIn?.energyScore;

    final String label;
    final IconData icon;
    final Color accentColor;

    if (energyScore == null) {
      label = 'Not recorded yet';
      icon = Icons.battery_unknown_rounded;
      accentColor = theme.colorScheme.outline;
    } else {
      switch (energyScore) {
        case 1:
          label = 'Completely Drained';
          icon = Icons.battery_alert_rounded;
          accentColor = Colors.red.shade400;
          break;
        case 2:
          label = 'Low Energy';
          icon = Icons.battery_2_bar_rounded;
          accentColor = Colors.orange.shade400;
          break;
        case 3:
          label = 'Moderate Energy';
          icon = Icons.battery_4_bar_rounded;
          accentColor = Colors.amber.shade600;
          break;
        case 4:
          label = 'Good Energy';
          icon = Icons.battery_5_bar_rounded;
          accentColor = Colors.lightGreen.shade600;
          break;
        case 5:
          label = 'Fully Energized';
          icon = Icons.battery_full_rounded;
          accentColor = Colors.green.shade600;
          break;
        default:
          label = 'Energy Score: $energyScore';
          icon = Icons.battery_std_rounded;
          accentColor = theme.colorScheme.primary;
      }
    }

    return GestureDetector(
      onTap: () => _onEditEnergyTapped(context),
      behavior: HitTestBehavior.opaque,
      child: FrostedContainer(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Energy Score',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildEditHint(context),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (energyScore != null)
                Text(
                  '$energyScore/5',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  /// Small edit/lock hint shown on the editable check-in cards.
  Widget _buildEditHint(BuildContext context) {
    final isPro = Provider.of<AppState>(context, listen: false).isPro;
    return Icon(
      isPro ? Icons.edit_rounded : Icons.lock_rounded,
      size: 12,
      color: isPro
          ? Theme.of(context).colorScheme.primary.withOpacity(0.6)
          : const Color(0xFFFF6B9D),
    );
  }

  // ---------------------------------------------------------------------------
  // Editable check-in (Premium) — adjust energy / recovery and regenerate
  // ---------------------------------------------------------------------------

  /// Guards a Premium-only action; shows an upsell and returns false if the
  /// user isn't subscribed.
  bool _ensureProForEditing(BuildContext context) {
    final isPro = Provider.of<AppState>(context, listen: false).isPro;
    if (!isPro) {
      ProModalUtils.showFeatureUpsellModal(
        context,
        title: 'Premium Feature',
        message:
            'Adjusting your energy and recovery to regenerate today\'s plan is '
            'a Premium feature. Upgrade to Premium to fine-tune your plan '
            'anytime.',
        icon: Icons.tune_rounded,
      );
    }
    return isPro;
  }

  Future<void> _onEditEnergyTapped(BuildContext context) async {
    if (!_ensureProForEditing(context)) return;

    const options = <int, String>{
      1: 'Completely Drained',
      2: 'Low Energy',
      3: 'Moderate Energy',
      4: 'Good Energy',
      5: 'Fully Energized',
    };
    final current =
        Provider.of<CheckInState>(context, listen: false).todaysCheckIn?.energyScore;

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildEditSheet<int>(
        ctx,
        title: 'Update Energy',
        entries: options.entries
            .map((e) => _EditOption<int>(
                  value: e.key,
                  label: e.value,
                  trailing: '${e.key}/5',
                  selected: e.key == current,
                ))
            .toList(),
      ),
    );

    if (selected != null && selected != current) {
      await _applyCheckInUpdateAndRegenerate(energyScore: selected);
    }
  }

  Future<void> _onEditRecoveryTapped(BuildContext context) async {
    if (!_ensureProForEditing(context)) return;

    const options = <RecoveryStatus, String>{
      RecoveryStatus.wellRested: 'Well Rested',
      RecoveryStatus.sore: 'Sore',
      RecoveryStatus.fatigued: 'Fatigued',
      RecoveryStatus.recovering: 'Recovering',
    };
    final current = Provider.of<CheckInState>(context, listen: false)
        .todaysCheckIn
        ?.recoveryStatus;

    final selected = await showModalBottomSheet<RecoveryStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildEditSheet<RecoveryStatus>(
        ctx,
        title: 'Update Recovery',
        entries: options.entries
            .map((e) => _EditOption<RecoveryStatus>(
                  value: e.key,
                  label: e.value,
                  selected: e.key == current,
                ))
            .toList(),
      ),
    );

    if (selected != null && selected != current) {
      await _applyCheckInUpdateAndRegenerate(recoveryStatus: selected);
    }
  }

  /// Updates today's check-in with the new value(s) and regenerates the plan.
  Future<void> _applyCheckInUpdateAndRegenerate({
    int? energyScore,
    RecoveryStatus? recoveryStatus,
    AvailableTimeRange? availableTime,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final planState = Provider.of<WellnessPlanState>(context, listen: false);
    final preferredMethods =
        Provider.of<AppState>(context, listen: false).preferredMethods;

    final updated = await checkInState.updateEnergyAndRecovery(
      energyScore: energyScore,
      recoveryStatus: recoveryStatus,
      availableTime: availableTime,
    );

    await planState.regeneratePlan(user.uid, updated,
        preferredMethods: preferredMethods);
  }

  Widget _buildEditSheet<T>(
    BuildContext context, {
    required String title,
    required List<_EditOption<T>> entries,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? theme.cardColor : Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...entries.map((opt) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).pop(opt.value),
              title: Text(opt.label),
              trailing: opt.selected
                  ? Icon(Icons.check_circle_rounded,
                      color: theme.colorScheme.primary)
                  : (opt.trailing != null
                      ? Text(opt.trailing!,
                          style: TextStyle(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5)))
                      : null),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 4: Recovery Status Summary
  // ---------------------------------------------------------------------------

  Widget _buildRecoveryStatusSection(
      BuildContext context, CheckInState checkInState) {
    final theme = Theme.of(context);
    final recovery = checkInState.todaysCheckIn?.recoveryStatus;

    final String label;
    final IconData icon;
    final Color accentColor;

    if (recovery == null) {
      label = 'Not recorded yet';
      icon = Icons.hotel_rounded;
      accentColor = theme.colorScheme.outline;
    } else {
      switch (recovery.name) {
        case 'wellRested':
          label = 'Well Rested';
          icon = Icons.nights_stay_rounded;
          accentColor = Colors.indigo.shade400;
          break;
        case 'sore':
          label = 'Sore';
          icon = Icons.fitness_center_rounded;
          accentColor = Colors.orange.shade400;
          break;
        case 'fatigued':
          label = 'Fatigued';
          icon = Icons.bedtime_rounded;
          accentColor = Colors.deepPurple.shade300;
          break;
        case 'recovering':
          label = 'Recovering';
          icon = Icons.healing_rounded;
          accentColor = Colors.teal.shade400;
          break;
        default:
          label = recovery.name;
          icon = Icons.hotel_rounded;
          accentColor = theme.colorScheme.primary;
      }
    }

    return GestureDetector(
      onTap: () => _onEditRecoveryTapped(context),
      behavior: HitTestBehavior.opaque,
      child: FrostedContainer(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Recovery Status',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildEditHint(context),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }

  // ---------------------------------------------------------------------------
  // Section 4b: Available Time Summary (editable, Premium)
  // ---------------------------------------------------------------------------

  Widget _buildAvailableTimeSection(
      BuildContext context, CheckInState checkInState) {
    final theme = Theme.of(context);
    final time = checkInState.todaysCheckIn?.availableTime;

    final String label;
    if (time == null) {
      label = 'Not recorded yet';
    } else {
      switch (time) {
        case AvailableTimeRange.under10:
          label = 'Under 10 minutes';
          break;
        case AvailableTimeRange.range10_20:
          label = '10–20 minutes';
          break;
        case AvailableTimeRange.range20_40:
          label = '20–40 minutes';
          break;
        case AvailableTimeRange.range40_60:
          label = '40–60 minutes';
          break;
        case AvailableTimeRange.over60:
          label = 'Over an hour';
          break;
      }
    }

    final accentColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => _onEditAvailableTimeTapped(context),
      behavior: HitTestBehavior.opaque,
      child: FrostedContainer(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.schedule_rounded, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Available Time',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildEditHint(context),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 350.ms, duration: 400.ms);
  }

  Future<void> _onEditAvailableTimeTapped(BuildContext context) async {
    if (!_ensureProForEditing(context)) return;

    const options = <AvailableTimeRange, String>{
      AvailableTimeRange.under10: 'Under 10 minutes',
      AvailableTimeRange.range10_20: '10–20 minutes',
      AvailableTimeRange.range20_40: '20–40 minutes',
      AvailableTimeRange.range40_60: '40–60 minutes',
      AvailableTimeRange.over60: 'Over an hour',
    };
    final current = Provider.of<CheckInState>(context, listen: false)
        .todaysCheckIn
        ?.availableTime;

    final selected = await showModalBottomSheet<AvailableTimeRange>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildEditSheet<AvailableTimeRange>(
        ctx,
        title: 'Update Available Time',
        entries: options.entries
            .map((e) => _EditOption<AvailableTimeRange>(
                  value: e.key,
                  label: e.value,
                  selected: e.key == current,
                ))
            .toList(),
      ),
    );

    if (selected != null && selected != current) {
      await _applyCheckInUpdateAndRegenerate(availableTime: selected);
    }
  }

  // ---------------------------------------------------------------------------
  // Section 5: Daily Plan Card Area
  // ---------------------------------------------------------------------------

  Widget _buildDailyPlanSection(
      BuildContext context, WellnessPlanState planState) {
    final theme = Theme.of(context);
    final plan = planState.todaysPlan;

    if (plan == null) {
      // No plan exists — show prompt to start check-in (Requirement 4.8)
      return FrostedContainer(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.spa_rounded,
                size: 48,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                "Your Daily Plan",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start your check-in to generate today\'s plan',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: 400.ms, duration: 400.ms);
    }

    // Plan exists — show the full interactive Daily Plan card
    return DailyPlanCard(plan: plan)
        .animate()
        .fadeIn(delay: 400.ms, duration: 400.ms);
  }

  // Wellness Studio now lives in the "More" tab (see ExploreTabScreen), just
  // before the Life Toolkit card. The old Home "Recommended for You" studio
  // badge was removed as part of that move.
}


class UserProfileSheet extends StatefulWidget {
  const UserProfileSheet({super.key});

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  final _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isLoading = false;
  File? _selectedImage;
  String? _currentAvatarUrl;
  final ImagePicker _picker = ImagePicker();

  // Personal details (loaded from the Firestore users/{uid} doc).
  static const List<String> _ageRanges = [
    '18–24',
    '25–34',
    '35–44',
    '45–54',
    '55+',
  ];
  static const List<String> _genderOptions = ['female', 'male', 'other'];

  String? _ageRange;
  String _nationality = 'United States';
  String _nationalityFlag = '🇺🇸';
  String _gender = 'female';
  bool _isSavingDetails = false;

  // Baselines captured after load / save, used to detect unsaved edits to the
  // personal-details section (which only persists on "Save details").
  String? _initialAgeRange;
  String _initialNationality = 'United States';
  String _initialGender = 'female';
  bool _personalDetailsLoaded = false;

  /// True when the personal-details section has edits that haven't been saved.
  bool get _hasUnsavedDetails =>
      _personalDetailsLoaded &&
      (_ageRange != _initialAgeRange ||
          _nationality != _initialNationality ||
          _gender != _initialGender);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadPersonalDetails();
  }

  void _loadUserData() {
    final user = AuthService().currentUser;
    final metadataName = user?.displayName;
    final avatarUrl = user?.photoURL;

    _nameController.text = (metadataName != null && metadataName.trim().isNotEmpty)
        ? metadataName
        : (user?.email?.split('@').first ?? 'Traveler');
    _currentAvatarUrl = avatarUrl;
  }

  /// Loads age range, nationality, and gender from the Firestore profile doc.
  Future<void> _loadPersonalDetails() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      setState(() {
        final age = data['age_range'] as String?;
        _ageRange = (age != null && _ageRanges.contains(age)) ? age : null;
        _nationality = data['nationality'] as String? ?? 'United States';
        final g = data['gender'] as String?;
        _gender = (g != null && _genderOptions.contains(g)) ? g : 'female';
        // Resolve the flag emoji for the stored nationality if possible.
        try {
          final country = CountryService().findByName(_nationality);
          if (country != null) _nationalityFlag = country.flagEmoji;
        } catch (_) {}
        // Capture baselines for unsaved-change detection.
        _initialAgeRange = _ageRange;
        _initialNationality = _nationality;
        _initialGender = _gender;
        _personalDetailsLoaded = true;
      });
    } catch (e) {
      debugPrint('UserProfileSheet: Failed to load personal details: $e');
    }
  }

  void _pickNationality() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (country) {
        setState(() {
          _nationality = country.name;
          _nationalityFlag = country.flagEmoji;
        });
      },
    );
  }

  /// Persists age range, nationality, and gender to Firestore. Also merges
  /// nationality + gender into meal_planner_profile so the AI Meal Planner
  /// stays in sync (matching what onboarding writes).
  Future<void> _savePersonalDetails() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    setState(() => _isSavingDetails = true);
    try {
      final ref =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Merge nationality + gender into the existing meal_planner_profile map.
      final snap = await ref.get();
      final existing = snap.data()?['meal_planner_profile'];
      final mealProfile = <String, dynamic>{
        if (existing is Map) ...Map<String, dynamic>.from(existing),
        'nationality': _nationality,
        'gender': _gender,
      };

      await ref.set({
        'age_range': _ageRange,
        'nationality': _nationality,
        'gender': _gender,
        'meal_planner_profile': mealProfile,
      }, SetOptions(merge: true));

      // Keep the local meal-planner cache in sync (same key MealPlanRepository uses).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('meal_planner_profile', jsonEncode(mealProfile));

      // Saved successfully — reset the baselines so the sheet is no longer dirty.
      _initialAgeRange = _ageRange;
      _initialNationality = _nationality;
      _initialGender = _gender;

      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Details updated successfully!',
          icon: Icons.check_circle_rounded,
          iconColor: Colors.green,
        );
      }
    } catch (e) {
      debugPrint('UserProfileSheet: Failed to save personal details: $e');
      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Failed to update details. Please try again.',
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDetails = false);
    }
  }

  /// Handles the close button: if there are unsaved edits, confirms with the
  /// user before dismissing the sheet; otherwise pops immediately.
  Future<void> _handleClose() async {
    final dirty = _hasUnsavedDetails || _isEditingName;
    if (!dirty) {
      Navigator.pop(context);
      return;
    }

    final theme = Theme.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved profile changes. If you close now, they will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.pop(context);
    }
  }

  /// Editable personal-details card: age range, nationality, gender.
  Widget _buildPersonalDetailsSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    InputDecoration decoration(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'PERSONAL DETAILS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Age range.
          DropdownButtonFormField<String>(
            value: _ageRange,
            isExpanded: true,
            decoration: decoration('Age range'),
            hint: const Text('Select age range'),
            items: _ageRanges
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _ageRange = v),
          ),
          const SizedBox(height: 12),

          // Nationality picker.
          InkWell(
            onTap: _pickNationality,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: decoration('Nationality'),
              child: Row(
                children: [
                  Text(_nationalityFlag,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_nationality,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Gender chips.
          Text('Gender', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _genderOptions.map((g) {
              final selected = _gender == g;
              return ChoiceChip(
                label: Text(g[0].toUpperCase() + g.substring(1)),
                selected: selected,
                onSelected: (_) => setState(() => _gender = g),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Save button.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSavingDetails ? null : _savePersonalDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSavingDetails
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save details',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Preferred Wellness Methods section (moved from Settings). Uses the
  /// current [AppState] and lets the user pick their preferred methods; a
  /// minimum of 3 is required to save.
  Widget _buildPreferredMethodsSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.spa_outlined,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'PREFERRED WELLNESS METHODS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Consumer<AppState>(
            builder: (context, appState, _) =>
                _WellnessMethodsSelector(appState: appState),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 70);
      if (image != null) {
        setState(() => _selectedImage = File(image.path));
        await _saveProfileChanges(updateImage: true);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Failed to pick image: $e',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _saveProfileChanges({bool updateImage = false, String? specificAvatarUrl}) async {
    setState(() => _isLoading = true);
    try {
      debugPrint('Updating profile with name: ${_nameController.text.trim()}');

      // Update Firebase Auth user metadata
      await AuthService().updateUserMetadata(
        displayName: _nameController.text.trim(),
        avatarUrl: specificAvatarUrl,
      );

      // Reload user to get fresh data
      final refreshedUser = AuthService().currentUser;
      final newName = refreshedUser?.displayName;
      if (newName != null) {
        _nameController.text = newName;
      }

      final newAvatar = refreshedUser?.photoURL;
      if (newAvatar != null) {
        _currentAvatarUrl = newAvatar;
        if (specificAvatarUrl != null) {
          _selectedImage = null;
        }
      }

      await StorageService().syncProfile();

      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Profile updated successfully!',
          icon: Icons.check_circle_rounded,
          iconColor: Colors.green, // Keep success green
        );
        setState(() {
          if (!updateImage) _isEditingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Failed to update profile: $e',
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  final List<String> _avatarOptions = [
    'https://img.freepik.com/premium-vector/portrait-beautiful-women-round-frame-avatar-female-character-isolated-white-background_559729-213.jpg',
    'https://img.freepik.com/premium-vector/portrait-beautiful-women-round-frame-avatar-female-character-isolated-white-background_559729-216.jpg',
    'https://img.freepik.com/premium-vector/portrait-beautiful-women-round-frame-avatar-female-character-isolated-white-background_559729-215.jpg',
    'https://img.freepik.com/premium-vector/portrait-beautiful-women-round-frame-avatar-female-character-isolated-white-background_559729-211.jpg',
  ];

  Future<void> _showAvatarSelectionBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).cardColor
              : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Choose Avatar',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickImage();
                  },
                  icon: Icon(Icons.photo_library_rounded, size: 18, color: Theme.of(context).primaryColor),
                  label: Text(
                    'Gallery',
                    style: TextStyle(color: Theme.of(context).primaryColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _avatarOptions.length,
              itemBuilder: (context, index) {
                final url = _avatarOptions[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleAvatarSelection(url);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white24
                              : Colors.grey.shade200
                      ),
                    ),
                    child: ClipOval(
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: Icon(Icons.person, color: Colors.grey));
                        },
                        errorBuilder: (ctx, error, stackTrace) =>
                        const Center(child: Icon(Icons.error_outline, size: 20, color: Colors.grey)),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAvatarSelection(String url) async {
    setState(() {
      _selectedImage = null; // Clear local file if any
      _currentAvatarUrl = url;
    });
    await _saveProfileChanges(updateImage: true, specificAvatarUrl: url);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final email = user?.email ?? 'No email';

    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).cardColor
            : Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white24
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Profile Header with Avatar & Pencil
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    backgroundImage: _selectedImage != null
                        ? FileImage(_selectedImage!)
                        : (_currentAvatarUrl != null ? NetworkImage(_currentAvatarUrl!) as ImageProvider : null),
                    child: (_selectedImage == null && _currentAvatarUrl == null)
                        ? Text(
                      _nameController.text.isNotEmpty ? _nameController.text.characters.first.toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    )
                        : null,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _showAvatarSelectionBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).scaffoldBackgroundColor
                            : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
                        ],
                      ),
                      child: Icon(Icons.edit_rounded, size: 14, color: Theme.of(context).primaryColor),
                    ),
                  ),
                ),
                Consumer<AppState>(
                  builder: (context, appState, child) {
                    if (!appState.isPro) return const SizedBox.shrink();
                    return Positioned(
                      bottom: 0,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B9D),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B9D).withOpacity(0.3),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Display Name with Edit Pencil
            if (_isEditingName)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onSubmitted: (_) => _saveProfileChanges(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => _saveProfileChanges(),
                    ),
                  ],
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _nameController.text,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _isEditingName = true),
                    child: Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white38
                            : Colors.grey.shade400
                    ),
                  ),
                ],
              ),

            Text(
              email,
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.grey.shade500
              ),
            ),
            const SizedBox(height: 32),

            _buildPersonalDetailsSection(context),
            const SizedBox(height: 24),

            // Preferred Wellness Methods — moved here from Settings, sits
            // where the Home Screen Widget section used to be.
            _buildPreferredMethodsSection(context),
            const SizedBox(height: 24),


            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                  ),
                ),
              ),

            // Actions


            const Divider(height: 32),

            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context); // Close sheet
                    await AuthService().signOut();
                    if (context.mounted) {
                      // Navigate to AuthGateway and remove all previous routes
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.red),
                  label: const Text("Log Out", style: TextStyle(color: Colors.red)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.withOpacity(0.1)
                        : Colors.red.shade50,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
          ),
          // Close button — top-right corner, pops the sheet (with an unsaved
          // changes confirmation when needed).
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _handleClose,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOption(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
            const SizedBox(width: 16),
            Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                )
            ),
            const Spacer(),
            Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white24
                    : Colors.grey.shade400
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Animated gradient logo (retained from original)
// -----------------------------------------------------------------------------
class _AnimatedGradientLogo extends StatefulWidget {
  const _AnimatedGradientLogo();

  @override
  State<_AnimatedGradientLogo> createState() => _AnimatedGradientLogoState();
}

class _AnimatedGradientLogoState extends State<_AnimatedGradientLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12), // full cycle: sweep + pause
    )..repeat();

    // Sweep now plays during the first 60% of the cycle (was 35%) —
    // slower glide across the logo. Remaining 40% is the pause.
    _sweep = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final baseColor =
        Theme.of(context).textTheme.titleLarge?.color ?? Colors.black;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop, // confines the highlight to the logo's own shape — no bleed on dark backgrounds
          shaderCallback: (bounds) {
            final slide = _sweep.value;
            final double offset = -1.6 + (slide * 3.2);
            const double vectorLen = 0.9;

            return LinearGradient(
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.9),
                Colors.white,
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.0),
                Colors.transparent,
                Colors.transparent,
              ],
              stops: const [0.0, 0.46, 0.485, 0.495, 0.5, 0.505, 0.515, 0.54, 1.0],
              begin: Alignment(offset - vectorLen, offset - vectorLen),
              end: Alignment(offset + vectorLen, offset + vectorLen),
            ).createShader(bounds);
          },
          child: SvgPicture.asset(
            'assets/images/aiwellnesspal.svg',
            height: 44,
            fit: BoxFit.contain,
            // no colorFilter — keeps the native blue (#4A7FFC) and green (#008C1B) fills
          ),
        );
      },
    );
  }
}


/// A single selectable option in the editable check-in bottom sheet.
class _EditOption<T> {
  final T value;
  final String label;
  final String? trailing;
  final bool selected;

  const _EditOption({
    required this.value,
    required this.label,
    this.trailing,
    this.selected = false,
  });
}

/// Lets the user customize their preferred wellness methods (moved here from
/// Settings). Minimum 3 required to save (no maximum). Changes are persisted
/// via [AppState.setPreferredMethods] and immediately influence future
/// Today's Plan generation — no need to repeat onboarding.
class _WellnessMethodsSelector extends StatefulWidget {
  final AppState appState;
  const _WellnessMethodsSelector({required this.appState});

  @override
  State<_WellnessMethodsSelector> createState() =>
      _WellnessMethodsSelectorState();
}

class _WellnessMethodsSelectorState extends State<_WellnessMethodsSelector> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.appState.preferredMethods.toSet();
  }

  bool get _meetsMin => _selected.length >= kMinWellnessMethods;

  // Chip geometry constants — kept in sync with _buildMethodChip so width
  // measurement matches what's actually rendered.
  static const double _chipHSpacing = 8; // gap between chips in a row
  static const double _chipRunSpacing = 8; // gap between rows
  static const double _chipHPadding = 12; // horizontal padding inside a chip
  static const double _chipIconSize = 18;
  static const double _chipIconGap = 8; // gap between icon and label
  static const double _chipCheckWidth = 6 + 16; // gap + check icon (selected)
  static const double _chipBorder = 2; // max border width (both sides ≈ 2)

  /// Measures the rendered width of a chip for [method] given its selected
  /// state (selected chips are bold and show a trailing check).
  double _chipWidth(WellnessMethod method, ThemeData theme, bool isSelected) {
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
    );
    final tp = TextPainter(
      text: TextSpan(text: method.label, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var w = _chipHPadding * 2 +
        _chipIconSize +
        _chipIconGap +
        tp.width +
        _chipBorder;
    if (isSelected) w += _chipCheckWidth;
    return w.ceilToDouble();
  }

  /// Packs all method chips into the fewest rows that fit [maxWidth] using a
  /// first-fit-decreasing strategy: widest chips are placed first so smaller
  /// ones fill the gaps, minimizing the number of rows (and the section
  /// height). Falls back gracefully when a single chip exceeds [maxWidth].
  Widget _buildPackedChips(ThemeData theme, double maxWidth) {
    // Precompute each chip's width in its current selected state.
    final items = kWellnessMethods.map((m) {
      final selected = _selected.contains(m.id);
      return (method: m, width: _chipWidth(m, theme, selected), selected: selected);
    }).toList()
      // Widest first for a tighter first-fit-decreasing packing.
      ..sort((a, b) => b.width.compareTo(a.width));

    final rows = <List<({WellnessMethod method, double width, bool selected})>>[];
    final rowWidths = <double>[];

    for (final item in items) {
      var placed = false;
      for (var i = 0; i < rows.length; i++) {
        final used = rowWidths[i] + _chipHSpacing + item.width;
        if (used <= maxWidth) {
          rows[i].add(item);
          rowWidths[i] = used;
          placed = true;
          break;
        }
      }
      if (!placed) {
        rows.add([item]);
        rowWidths.add(item.width);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: _chipRunSpacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              for (var j = 0; j < rows[i].length; j++) ...[
                if (j > 0) const SizedBox(width: _chipHSpacing),
                _buildMethodChip(theme, rows[i][j].method),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMethodChip(ThemeData theme, WellnessMethod method) {
    final isSelected = _selected.contains(method.id);
    return GestureDetector(
      onTap: () => _toggle(method.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: _chipHPadding, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.08)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              method.icon,
              size: _chipIconSize,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: _chipIconGap),
            Text(
              method.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle,
                  size: 16, color: theme.colorScheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  /// Whether the current selection differs from what's already saved.
  bool get _isDirty {
    final saved = widget.appState.preferredMethods.toSet();
    return !(saved.length == _selected.length &&
        saved.containsAll(_selected));
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _save() {
    if (!_meetsMin) return;
    widget.appState.setPreferredMethods(_selected.toList());
    FocusScope.of(context).unfocus();
    WellnessPalSnackBar.show(context, message: 'Wellness preferences saved');
    setState(() {}); // Refresh dirty state.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _selected.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the wellness approaches you enjoy most. We\'ll prioritize '
          'them when creating your daily plans.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _meetsMin
              ? '$count method${count == 1 ? '' : 's'} selected'
              : 'Select at least $kMinWellnessMethods wellness methods.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: _meetsMin ? theme.colorScheme.primary : theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // Measured first-fit bin-packing: each chip's real width is computed
        // against the available row width and chips are packed greedily so the
        // fewest rows are used (tightest possible layout for variable widths).
        LayoutBuilder(
          builder: (context, constraints) {
            return _buildPackedChips(theme, constraints.maxWidth);
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_meetsMin && _isDirty) ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Save preferences',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
