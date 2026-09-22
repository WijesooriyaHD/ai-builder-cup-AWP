import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show globalNavigatorKey;
import '../providers/app_state.dart';
import '../services/live_conversation_service.dart';
import '../services/pal_wake_word_service.dart';
import 'voice_assistant_sheet.dart';

/// Mounts the foreground wake-word listener and opens the Live pal on match.
///
/// Kept as a thin coordinator so:
///  - Lifecycle handling is centralised (listener stops in background, and
///    resumes when the app returns to the foreground).
///  - The wake service never runs during an in-flight Live conversation or
///    while the voice sheet is already visible, avoiding mic contention.
///  - Removing this widget removes the feature entirely — no scattered hooks.
///
/// IMPORTANT: reconciliation is driven by explicit change listeners
/// (AppState + LiveConversationService) and app lifecycle — NOT from build().
/// Driving imperative mic start/stop from build() caused a reconcile-per-frame
/// storm that could throw from the speech plugin.
class PalWakeWordCoordinator extends StatefulWidget {
  const PalWakeWordCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<PalWakeWordCoordinator> createState() =>
      _PalWakeWordCoordinatorState();
}

class _PalWakeWordCoordinatorState extends State<PalWakeWordCoordinator>
    with WidgetsBindingObserver {
  final PalWakeWordService _wake = PalWakeWordService();

  AppState? _appState;
  LiveConversationService? _liveService;

  bool _appIsResumed = true;
  bool _sheetOpen = false;
  bool _reconcileQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the providers ONCE (re-subscribe only if the instances
    // change, which they normally never do). Their notifications drive
    // reconciliation, replacing the previous build()-driven approach.
    final appState = context.read<AppState>();
    if (!identical(appState, _appState)) {
      _appState?.removeListener(_onDependencyChanged);
      _appState = appState;
      appState.addListener(_onDependencyChanged);
    }
    final liveService = context.read<LiveConversationService>();
    if (!identical(liveService, _liveService)) {
      _liveService?.removeListener(_onDependencyChanged);
      _liveService = liveService;
      liveService.addListener(_onDependencyChanged);
    }
    _scheduleReconcile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState?.removeListener(_onDependencyChanged);
    _liveService?.removeListener(_onDependencyChanged);
    _wake.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    _scheduleReconcile();
  }

  void _onDependencyChanged() => _scheduleReconcile();

  /// Collapses bursts of provider notifications into a single reconcile on the
  /// next microtask, so we never thrash the recognizer.
  void _scheduleReconcile() {
    if (_reconcileQueued) return;
    _reconcileQueued = true;
    Future.microtask(() {
      _reconcileQueued = false;
      if (mounted) _reconcile();
    });
  }

  void _reconcile() {
    final appState = _appState;
    final liveService = _liveService;
    if (appState == null || liveService == null) return;

    final eligible = appState.alwaysListenForPal &&
        appState.liveChatPal &&
        LiveConversationService.isAvailable;

    final shouldListen = eligible &&
        _appIsResumed &&
        !_sheetOpen &&
        liveService.state == LiveConversationState.idle;

    if (shouldListen) {
      // start() is idempotent (no-ops if already running) and self-initializes.
      _wake.start(onWake: _openLivePal);
    } else {
      _wake.stop();
      // Keep the recognizer warm while the feature is on but temporarily
      // paused (e.g. a conversation is active), so the next start is instant.
      if (eligible && _appIsResumed) {
        _wake.warmUp();
      }
    }
  }

  Future<void> _openLivePal() async {
    if (_sheetOpen) return;
    final navigator = globalNavigatorKey.currentState;
    if (navigator == null) return;
    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: navigator.context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceAssistantSheet(),
      );
    } finally {
      _sheetOpen = false;
      // The Live sheet just held the mic + audio session. iOS releases those
      // asynchronously, so wait before the wake recognizer reclaims the input
      // node — reclaiming too early races the native audio-unit teardown and
      // can crash speech_to_text. Be generous; correctness over latency here.
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) _reconcile();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
