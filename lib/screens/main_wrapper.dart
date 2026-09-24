import 'package:flutter/material.dart';
import 'dart:async';

import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/home_screen.dart';
import '../screens/wellness_intentions_screen.dart';
import '../screens/habit_builder_screen.dart';
import '../screens/wellness_reflection_screen.dart';
import '../screens/settings_screen.dart';
import '../services/voice_command_service.dart';
import '../services/live_conversation_service.dart';
import '../services/app_navigation_service.dart';
import '../services/life_tool_registry.dart';
import '../main.dart' show globalNavigatorKey;
import '../widgets/voice_assistant_sheet.dart';


class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _selectedIndex = 0;
  AppNavigationService? _nav;
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    // Guarantee Pro status is freshly resolved whenever the authenticated
    // home mounts (every login / hot restart), so the home badge and premium
    // voice options reflect the true subscription state. This is independent
    // of the once-per-session background sync path.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().updateProStatus(forceRefresh: true);
      }
    });

    // Deep-link from a home-screen widget tap to the matching bottom tab.
    // Handles both the cold-start launch URI and taps while the app is alive.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWidgetDeepLinks());
  }

  /// Wires up home-screen widget "open the app" taps to bottom-tab navigation.
  ///
  /// The native widgets attach a launch URI like
  /// `aiwellnesspal://open?screen=habit_builder`. On a cold start the URI is
  /// available via [HomeWidget.initiallyLaunchedFromHomeWidget]; while the app
  /// is already running it arrives on the [HomeWidget.widgetClicked] stream.
  Future<void> _initWidgetDeepLinks() async {
    try {
      final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _handleWidgetUri(launchUri);
    } catch (e) {
      debugPrint('MainWrapper: initiallyLaunchedFromHomeWidget error: $e');
    }

    _widgetClickSub =
        HomeWidget.widgetClicked.listen(_handleWidgetUri, onError: (e) {
      debugPrint('MainWrapper: widgetClicked stream error: $e');
    });
  }

  /// Maps a widget launch URI to a bottom tab and switches to it.
  /// Only reacts to the dedicated `open` host so it never collides with the
  /// background toggle/refresh URIs handled in [AppState.backgroundCallback].
  void _handleWidgetUri(Uri? uri) {
    if (uri == null || uri.host != 'open') return;
    final screen = uri.queryParameters['screen'];
    if (screen == null || screen.isEmpty) return;

    // Life-toolkit widgets deep-link with `screen=tool_<id>`. These open a
    // full tool screen (pushed on the root navigator) rather than switching a
    // bottom tab — mirroring the "Jump to tool" grid's Navigator.push.
    if (screen.startsWith('tool_')) {
      _openTool(screen.substring('tool_'.length));
      return;
    }

    AppTab? tab;
    switch (screen) {
      case 'home':
        tab = AppTab.home;
        break;
      case 'intentions':
        tab = AppTab.intentions;
        break;
      case 'habit_builder':
        tab = AppTab.habitBuilder;
        break;
      case 'reflection':
        tab = AppTab.reflection;
        break;
      case 'settings':
        tab = AppTab.settings;
        break;
    }
    if (tab == null || !mounted) return;

    // Route through AppNavigationService so MainWrapper's existing listener
    // performs the tab switch (also covers the case where this arrives before
    // the first frame).
    context.read<AppNavigationService>().goToTab(tab);
  }

  /// Pushes the Life-toolkit tool screen for [toolId] onto the root navigator,
  /// matching how the "Jump to tool" grid opens each tool.
  void _openTool(String toolId) {
    final tool = lifeToolById(toolId);
    if (tool == null) return;
    // Use the root navigator (via the global key) so this works regardless of
    // which bottom tab is currently shown, and avoids pushing inside a nested
    // navigator. Post-frame guards against a cold-start push before the first
    // frame is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = globalNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(MaterialPageRoute(builder: tool.builder));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for tab-switch requests (e.g. from the voice assistant).
    final nav = context.read<AppNavigationService>();
    if (_nav != nav) {
      _nav?.removeListener(_onNavRequest);
      _nav = nav;
      _nav!.addListener(_onNavRequest);
    }
  }

  void _onNavRequest() {
    final target = _nav?.requestedIndex ?? 0;
    if (target != _selectedIndex && mounted) {
      setState(() => _selectedIndex = target);
    }
  }

  @override
  void dispose() {
    _nav?.removeListener(_onNavRequest);
    _widgetClickSub?.cancel();
    super.dispose();
  }

  final List<Widget> _pages = const [
     HomeScreen(),
     WellnessIntentionsScreen(),
     HabitBuilderScreen(),
     WellnessReflectionScreen(),
     SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Only if using a transparent/floating navbar
      body: IndexedStack(
         index: _selectedIndex,
         children: _pages,
      ),
      floatingActionButton: _buildVoiceFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 24, right: 24, top: 10, bottom: 32),
        height: 64, // Explicit height for the pill
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1E2124) // Dark surface
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Theme.of(context).brightness == Brightness.dark
              ? Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.0,
                )
              : null,
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.dark)
              BoxShadow(
                color: Colors.white.withOpacity(0.05),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
            _buildNavItem(1, Icons.self_improvement_outlined, Icons.self_improvement_rounded),
            _buildNavItem(2, Icons.checklist_rounded, Icons.checklist_rounded),
            _buildNavItem(3, Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
            _buildNavItem(4, Icons.settings_outlined, Icons.settings_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceFab(BuildContext context) {
    final theme = Theme.of(context);
    // Watch BOTH pals so the mic reflects whichever one is running (the Live
    // pal is selected in Settings → AI Voice).
    return Consumer2<VoiceCommandService, LiveConversationService>(
      builder: (context, voiceService, liveService, _) {
        final isActive =
            voiceService.state != VoiceAssistantState.idle ||
                liveService.state == LiveConversationState.connecting ||
                liveService.state == LiveConversationState.active;
        return Padding(
          padding: const EdgeInsets.only(bottom: 80),
          // TAP → open + start the pal. LONG-PRESS → open the Wellness Pal
          // window WITHOUT starting a conversation, so the user can see their
          // Recent Conversations first (then tap the orb to talk).
          child: GestureDetector(
            onLongPress: () => _showVoiceAssistant(context, autoStart: false),
            child: FloatingActionButton(
              onPressed: () => _showVoiceAssistant(context),
              backgroundColor: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surface,
              elevation: isActive ? 8 : 4,
              child: Icon(
                isActive ? Icons.mic : Icons.mic_none_rounded,
                color: isActive ? Colors.white : theme.colorScheme.primary,
                size: 26,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVoiceAssistant(BuildContext context, {bool autoStart = true}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceAssistantSheet(autoStartLive: autoStart),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 64,
        width: 64,
        alignment: Alignment.center,
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected 
              ? Theme.of(context).colorScheme.primary 
              : (Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white54 
                  : Colors.grey.shade400),
          size: 28,
        ),
      ),
    );
  }
}
