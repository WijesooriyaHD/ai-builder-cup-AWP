import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/home_screen.dart';
import '../screens/wellness_intentions_screen.dart';
import '../screens/habit_builder_screen.dart';
import '../screens/wellness_reflection_screen.dart';
import '../screens/settings_screen.dart';
import '../services/voice_command_service.dart';
import '../services/app_navigation_service.dart';
import '../widgets/voice_assistant_sheet.dart';


class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _selectedIndex = 0;
  AppNavigationService? _nav;

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
    return Consumer<VoiceCommandService>(
      builder: (context, voiceService, _) {
        final isActive = voiceService.state != VoiceAssistantState.idle;
        return Padding(
          padding: const EdgeInsets.only(bottom: 80),
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
        );
      },
    );
  }

  void _showVoiceAssistant(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceAssistantSheet(),
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
