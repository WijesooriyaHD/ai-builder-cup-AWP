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
  bool _appIsResumed = true;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wake.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    _reconcile();
  }

  void _reconcile() {
    final appState = context.read<AppState>();
    final liveService = context.read<LiveConversationService>();
    final shouldListen = _appIsResumed &&
        !_sheetOpen &&
        appState.alwaysListenForPal &&
        appState.liveChatPal &&
        LiveConversationService.isAvailable &&
        liveService.state == LiveConversationState.idle;

    if (shouldListen) {
      _wake.start(onWake: _openLivePal);
    } else {
      _wake.stop();
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
      if (mounted) _reconcile();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the relevant slices so start/stop follows setting changes without
    // needing an explicit subscription in every host.
    context.select<AppState, bool>((s) => s.alwaysListenForPal);
    context.select<AppState, bool>((s) => s.liveChatPal);
    context.select<LiveConversationService, LiveConversationState>(
        (s) => s.state);
    // Reconcile after the build settles so provider reads are safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reconcile();
    });
    return widget.child;
  }
}
