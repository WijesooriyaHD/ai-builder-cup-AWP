import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/personalization_state.dart';
import '../providers/wellness_plan_state.dart';
import '../services/auth_service.dart';
import '../services/live_conversation_service.dart';
import '../services/voice_command_service.dart';
import '../data/ai_voices.dart';
import '../screens/customer_center_screen.dart';
import '../screens/faq_screen.dart';
import '../services/revenue_cat_service.dart';
import '../utils/pro_modal_utils.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../widgets/frosted_container.dart';
import '../theme/wellness_themes.dart';
import '../exceptions/premium_feature_exception.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// SharedPreferences key for disabling AI insights.
  static const String _aiInsightsDisabledKey = 'wellness_ai_insights_disabled';

  bool _aiInsightsDisabled = false;
  String _aiInsightsSummary = '';
  bool _summaryLoaded = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadAiInsightsPreference();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_summaryLoaded) {
      _summaryLoaded = true;
      _loadAiInsightsSummary();
    }
  }

  Future<void> _loadAiInsightsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final disabled = prefs.getBool(_aiInsightsDisabledKey) ?? false;
      if (mounted) {
        setState(() {
          _aiInsightsDisabled = disabled;
        });
      }
    } catch (e) {
      debugPrint('SettingsScreen: Failed to load AI insights preference: $e');
    }
  }

  void _loadAiInsightsSummary() {
    final personalization =
        Provider.of<PersonalizationState>(context, listen: false);
    setState(() {
      _aiInsightsSummary = personalization.summarizePreferences();
    });
  }

  Future<void> _toggleAiInsights(bool disabled) async {
    setState(() {
      _aiInsightsDisabled = disabled;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_aiInsightsDisabledKey, disabled);
    } catch (e) {
      debugPrint('SettingsScreen: Failed to persist AI insights preference: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Customize AI Wellness Pal", 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.titleLarge?.color,
          )
        ),
        backgroundColor: Colors.transparent, // Transparent to show scaffold background
        elevation: 0,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return ListView(
            padding: const EdgeInsets.all(16), // Tighter padding for card layout
            children: [
              _buildSubscriptionSection(context),
              const SizedBox(height: 16),

              // Home Screen Widget — moved here from the profile sheet.
              _buildCard(
                context,
                title: "Home Screen Widget",
                child: _buildWidgetsSection(context),
              ),
              const SizedBox(height: 16),

              _buildCard(
                context,
                title: "AI Voice",
                child: _buildAiVoiceSelector(context, appState),
              ),
              const SizedBox(height: 16),

              _buildCard(
                context,
                title: "Appearance",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildThemeToggle(context, appState),
                    const SizedBox(height: 24),
                    Text("Season", style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildSeasonToggle(context, appState),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildThemesSection(context, appState),
              const SizedBox(height: 16),
              
              _buildCard(
                context,
                title: "Readability",
                child: Column(
                  children: [
                    _buildTextScaleSlider(context, appState),
                    const SizedBox(height: 16),
                    // Preview box inside the readability card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                           color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.black.withOpacity(0.3) 
                              : Colors.grey.shade50,
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(
                             color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withOpacity(0.1) 
                                : Colors.grey.shade100
                           ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Preview", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(
                              "This is how your text will look.",
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              _buildAiInsightsSection(context),
              const SizedBox(height: 16),
              
              _buildCard(
                context,
                title: "Support",
                child: Column(
                  children: [
                    _buildSettingsTile(
                      context,
                      icon: Icons.help_outline_rounded,
                      title: "FAQ & Help",
                      subtitle: "Learn about core features",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const FaqScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildCard(
                context,
                title: "Account",
                child: _buildLogoutButton(context),
              ),
              const SizedBox(height: 16),

              _buildDangerZoneSection(context),
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Home Screen Widget (moved here from the profile sheet)
  // ---------------------------------------------------------------------------

  /// Tappable row that opens the Today's Plan home-screen widget sheet.
  Widget _buildWidgetsSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showHomeWidgetsBottomSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.dashboard_rounded,
                size: 20, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Plan Widget",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Add Today's Plan to your home screen",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: isDark ? Colors.white24 : Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  void _showHomeWidgetsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final primary = Theme.of(sheetContext).primaryColor;
        final plan =
            Provider.of<WellnessPlanState>(sheetContext, listen: false)
                .todaysPlan;

        return Container(
          margin: const EdgeInsets.all(16),
          // Cap the sheet so it never exceeds the screen; the content scrolls
          // if it's taller than the available space.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Theme.of(sheetContext).cardColor : Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.today_rounded,
                          color: primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        "Today's Plan Widget",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  "Add the Today's Plan widget to your phone's home screen to "
                  "see your daily wellness actions and tick them off — right "
                  "from your home screen. It stays in sync with the app "
                  "automatically.",
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 20),
                // Live preview of what the widget currently shows.
                _buildWidgetPreview(sheetContext, plan, primary, isDark),
                const SizedBox(height: 20),
                // How-to hint.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Long-press your home screen, tap Widgets, and add "
                        "\"AI Wellness\" to place it.",
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A compact preview mirroring what the native Today's Plan widget shows.
  Widget _buildWidgetPreview(
      BuildContext context, dynamic plan, Color primary, bool isDark) {
    final hasPlan = plan != null && (plan.actions as List).isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: hasPlan
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.todaysFocus as String,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                ...(plan.actions as List).take(3).map((a) {
                  final done = a.isCompleted as bool;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          done
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color: done ? primary : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.title as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              decoration:
                                  done ? TextDecoration.lineThrough : null,
                              color: done
                                  ? Colors.grey
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            )
          : Row(
              children: [
                Icon(Icons.today_rounded,
                    color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Complete your check-in to see your plan on the widget.',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAiInsightsSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI INSIGHTS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white70 : Colors.black,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _aiInsightsSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Disable AI Insights',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Switch.adaptive(
                  value: _aiInsightsDisabled,
                  onChanged: (value) => _toggleAiInsights(value),
                ),
              ],
            ),
            if (_aiInsightsDisabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'AI Insight card is hidden on the Home screen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesSection(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = appState.themeColor;

    return _buildCard(
      context,
      title: "Theme",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick a wellness theme. Each theme sets your accent color and '
            'background across the whole app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),

          // Live accent preview — reflects the currently selected theme color.
          _buildAccentPreview(context, accent),
          const SizedBox(height: 24),

          // Single horizontally-scrollable row of theme swatches.
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: wellnessThemes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final theme = wellnessThemes[index];
                final isSelected =
                    appState.themeColor.value == theme.seedColor.value;
                return _buildThemeTile(context, appState, theme, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A small preview strip showing how the selected accent color looks applied
  /// to common UI elements (button, chip, progress).
  Widget _buildAccentPreview(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Sample "button".
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Text(
              'Button',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sample "chip".
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.4)),
            ),
            child: Text(
              'Chip',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sample progress.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: 0.65,
                minHeight: 8,
                backgroundColor: accent.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeTile(
    BuildContext context,
    AppState appState,
    WellnessThemeConfig theme,
    bool isSelected,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        try {
          appState.setWellnessTheme(theme);
        } on PremiumFeatureException {
          _showThemePaywall(context, theme);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.seedColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black)
                        : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.seedColor.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
              ),
              if (theme.isPremium && !appState.isPro)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            theme.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemePaywall(BuildContext context, WellnessThemeConfig theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? Theme.of(ctx).cardColor
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.seedColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.seedColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Unlock ${theme.name} Theme',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Upgrade to Premium to access the ${theme.name} theme and other premium wellness themes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(ctx)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Upgrade to Premium',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Maybe Later', style: TextStyle(color: Colors.grey[400])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiVoiceSelector(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedId = appState.aiVoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose how your wellness pal sounds.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
        ),
        const SizedBox(height: 16),
        ...kAiVoices.map((voice) {
          final isSelected = voice.id == selectedId;
          final isLocked = voice.isPremium && !appState.isPro;
          return _buildVoiceTile(
              context, appState, voice, isSelected, isLocked);
        }),
        const SizedBox(height: 8),
        Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
        const SizedBox(height: 8),
        _buildLiveChatPalToggle(context, appState),
        if (LiveConversationService.isAvailable && appState.liveChatPal) ...[
          const SizedBox(height: 12), // Reduced from 18
          _buildLivePalVoiceSelector(context, appState),
          const SizedBox(height: 12),
          _buildAlwaysListenForPalToggle(context, appState),
        ],
        const SizedBox(height: 16),
        Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
        const SizedBox(height: 8),
        _buildForceEnglishToggle(context, appState),
      ],
    );
  }

  /// Voice picker for the real-time Live chat pal. These are server-side Gemini
  /// voices, so there's no local preview — the voice is applied when the next
  /// conversation starts.
  Widget _buildLivePalVoiceSelector(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedId = appState.livePalVoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // Added to minimize height
      children: [
        Text(
          'LIVE CHAT PAL VOICE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
              ),
        ),
        const SizedBox(height: 4), // Reduced from 6
        Text(
          'Test these voices during live conversations.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
        ),
        const SizedBox(height: 8), // Reduced from 12
        // Make the voice list more compact
        ...kLivePalVoices.map((voice) {
          final isSelected = voice.id == selectedId;
          final isLocked = voice.isPremium && !appState.isPro;
          return _buildLivePalVoiceTile(
              context, appState, voice, isSelected, isLocked);
        }),
      ],
    );
  }

  Widget _buildLivePalVoiceTile(
    BuildContext context,
    AppState appState,
    LivePalVoiceOption voice,
    bool isSelected,
    bool isLocked,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isLocked
            ? null
            : () {
                try {
                  appState.setLivePalVoice(voice.id);
                } on PremiumFeatureException {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${voice.name} is a Premium voice.'),
                    ),
                  );
                }
              },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withOpacity(0.1)
                : (isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(voice.icon, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          voice.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (isLocked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock_rounded,
                              size: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.4)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      voice.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// "Always listen for 'Pal'" — a foreground wake-word toggle. When on, the
  /// app listens for "Hey Pal" or "Pal" while it is on screen and opens the
  /// Live pal automatically. iOS does not permit third-party apps to keep the
  /// mic on while backgrounded, so this only takes effect in the foreground.
  Widget _buildAlwaysListenForPalToggle(
      BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = appState.alwaysListenForPal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Always listen for "Pal"',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) => appState.setAlwaysListenForPal(value),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 48),
          child: Text(
            enabled
                ? 'Say "Hey Pal" or "Pal" and I\'ll open the live conversation. '
                    'Only works while the app is on screen.'
                : 'Turn on to open the live pal hands-free — just say "Hey Pal" '
                    'or "Pal" while the app is on screen.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }

  /// "Live chat Pal" — when on, the mic button opens the real-time streaming
  /// conversation pal instead of the default tap-to-speak pal. Off by default.
  Widget _buildLiveChatPalToggle(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = appState.liveChatPal;
    // The Live pal ships behind FeatureFlags.liveConversationMode. If this
    // build doesn't include it, the toggle would silently do nothing — so hide
    // it entirely rather than offering a switch that can't take effect.
    if (!LiveConversationService.isAvailable) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Live Chat Pal',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) => appState.setLiveChatPal(value),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 48),
          child: Text(
            enabled
                ? 'Tapping the mic starts a real-time conversation — talk '
                    'naturally and your pal responds as you speak.'
                : 'Tapping the mic uses the standard pal: it listens, then '
                    'replies. Turn this on for a flowing, real-time chat.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }

  /// "Always speak English" — when on, the voice pal replies only in English
  /// even if the user speaks another language. Off by default, in which case
  /// the pal mirrors whatever language it hears.
  Widget _buildForceEnglishToggle(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = appState.forceEnglishVoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Always speak English',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) => appState.setForceEnglishVoice(value),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 48),
          child: Text(
            enabled
                ? 'Your pal replies only in English, even if you speak another '
                    'language.'
                : 'Your pal replies in whatever language you speak. Turn this '
                    'on to keep every conversation in English.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceTile(
    BuildContext context,
    AppState appState,
    AiVoiceOption voice,
    bool isSelected,
    bool isLocked,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          try {
            appState.setAiVoice(voice.id);
            // Apply + preview the newly selected voice.
            context.read<VoiceCommandService>().previewVoice(voice.id);
          } on PremiumFeatureException {
            _showVoicePaywall(context, voice);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withOpacity(0.1)
                : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(voice.icon, color: primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          voice.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (voice.isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B9D).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PREMIUM',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: Color(0xFFFF6B9D),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      voice.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLocked)
                Icon(Icons.lock_rounded, size: 18, color: primary)
              else if (isSelected)
                Icon(Icons.check_circle_rounded, size: 22, color: primary)
              else
                Icon(Icons.play_circle_outline_rounded,
                    size: 22,
                    color: isDark ? Colors.white38 : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _showVoicePaywall(BuildContext context, AiVoiceOption voice) {
    final primary = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? Theme.of(ctx).cardColor
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(voice.icon, size: 48, color: primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Unlock the ${voice.name} Voice',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Premium voices let you personalize how your wellness pal '
              'sounds. Upgrade to Premium to unlock ${voice.name} and more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(ctx)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ProModalUtils.openUpgrade(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Upgrade to Premium',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Maybe Later',
                  style: TextStyle(color: Colors.grey[400])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white.withOpacity(0.05) 
              : Colors.grey.shade100
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white70 
                  : Colors.black, // Adapt title color
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildSeasonToggle(BuildContext context, AppState appState) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.black.withOpacity(0.3) 
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final segmentWidth = width / 2;
          
          Alignment alignment = appState.isWinterMode ? Alignment.centerRight : Alignment.centerLeft;

          return Stack(
            children: [
              AnimatedAlign(
                alignment: alignment,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: segmentWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Theme.of(context).cardColor 
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                   _buildSlidingOption(
                    context, 
                    icon: Icons.wb_sunny_rounded, 
                    label: "Normal", 
                    isActive: !appState.isWinterMode,
                    onTap: () => appState.setWinterMode(false),
                  ),
                   _buildSlidingOption(
                    context, 
                    icon: Icons.ac_unit_rounded, 
                    label: "Winter", 
                    isActive: appState.isWinterMode,
                    onTap: () => appState.setWinterMode(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context, AppState appState) {
    return Container(
      height: 56, // Fixed height for consistency
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.black.withOpacity(0.3) 
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final segmentWidth = width / 2;
          
          // Determine alignment based on selection
          Alignment alignment = Alignment.centerLeft;
          if (appState.themeMode == ThemeMode.dark) {
            alignment = Alignment.centerRight;
          }

          return Stack(
            children: [
              // Sliding Indicator
              AnimatedAlign(
                alignment: alignment,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: segmentWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Theme.of(context).cardColor 
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                ),
              ),
              // Text Labels Row
              Row(
                children: [
                   _buildSlidingOption(
                    context, 
                    icon: Icons.light_mode_rounded, 
                    label: "Light", 
                    isActive: appState.themeMode == ThemeMode.light || appState.themeMode == ThemeMode.system, // Fallback if system somehow sticks
                    onTap: () => appState.setThemeMode(ThemeMode.light),
                  ),
                   _buildSlidingOption(
                    context, 
                    icon: Icons.dark_mode_rounded, 
                    label: "Dark", 
                    isActive: appState.themeMode == ThemeMode.dark,
                    onTap: () => appState.setThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSlidingOption(BuildContext context, {required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(
               icon, 
               size: 20, 
               color: isActive 
                   ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black) 
                   : Colors.grey.shade600
             ),
             const SizedBox(height: 4),
             Text(
               label, 
               style: TextStyle(
                 fontSize: 12, 
                 fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                 color: isActive 
                     ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black) 
                     : Colors.grey.shade600
               )
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextScaleSlider(BuildContext context, AppState appState) {
     return Column(
       children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             const Text("A", style: TextStyle(fontSize: 12)),
             Expanded(
               child: Slider(
                 value: appState.textScaleFactor.clamp(0.8, 1.3),
                 min: 0.8,
                 max: 1.3,
                 divisions: 5,
                 label: "${appState.textScaleFactor.toStringAsFixed(1)}x",
                 onChanged: (value) => appState.setTextScaleFactor(value),
               ),
             ),
             const Text("A", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
           ],
         ),
         Text(
           "${(appState.textScaleFactor * 100).toInt()}%",
           style: Theme.of(context).textTheme.labelSmall,
         )
       ],
     );
  }

  Widget _buildSubscriptionSection(BuildContext context) {
    final revenueCatService = RevenueCatService();
    
    return FutureBuilder<SubscriptionStatus>(
      future: revenueCatService.getSubscriptionStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? SubscriptionStatus.none;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark 
                  ? [
                      const Color(0xFF322E40), // Premium Surface
                      const Color(0xFF2A2635), // Slightly darker
                    ]
                  : [
                      const Color(0xFFFFF5F7),
                      const Color(0xFFF0F9FF),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withOpacity(0.1) 
                  : Theme.of(context).colorScheme.primary.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SvgPicture.asset(
                              'assets/images/aiwellnesspal.svg',
                              height: 40,
                              // colorFilter: ColorFilter.mode(
                              //   Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                              //   BlendMode.srcIn,
                              // ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'PREMIUM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isLoading)
                          Text(
                            "Loading...",
                            style: TextStyle(
                              fontSize: 14, 
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.white70 
                                  : Colors.grey.shade600
                            ),
                          )
                        else
                          Text(
                            _getStatusText(status),
                            style: TextStyle(
                              fontSize: 14, 
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.white70 
                                  : Colors.grey.shade600
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Non-subscribers go straight to the paywall; existing
                    // subscribers go to the Manage Subscription screen.
                    if (status == SubscriptionStatus.none) {
                      ProModalUtils.openUpgrade(context);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const CustomerCenterScreen(),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    status == SubscriptionStatus.none ? 'Upgrade to Premium' : 'Manage Subscription',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStatusText(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.monthly:
        return 'Active • Monthly Plan';
      case SubscriptionStatus.yearly:
        return 'Active • Yearly Plan';
      case SubscriptionStatus.other:
        return 'Active Subscription';
      case SubscriptionStatus.none:
        return 'Unlock premium features';
    }
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () async {
          try {
            await AuthService().signOut();
            // AuthState stream in main.dart will handle navigation
          } catch (e) {
            WellnessPalSnackBar.show(
              context,
              message: 'Error logging out: $e',
              icon: Icons.error_outline_rounded,
              isError: true,
            );
          }
        },
        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
        label: const Text(
          "Log Out",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.redAccent.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white24 : Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  // --- Danger Zone: Account Deletion ---

  Widget _buildDangerZoneSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DANGER ZONE',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.redAccent.shade200,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _isDeletingAccount ? null : () => _showDeleteAccountDialog(context),
              icon: _isDeletingAccount
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.redAccent,
                      ),
                    )
                  : const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              label: Text(
                _isDeletingAccount ? "Deleting Account..." : "Delete Account",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.redAccent.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user signed in with Google
    final isGoogleUser = user.providerData.any((p) => p.providerId == 'google.com');

    if (isGoogleUser) {
      // Google user — simple confirmation, no password needed
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: const Text(
              'This action is permanent and cannot be undone. '
              'All your data will be deleted, including your wellness plans, '
              'check-in history, journal entries, intentions, and uploaded files.\n\n'
              'You will be asked to verify your Google account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text(
                  'Delete My Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed == true && mounted) {
        await _performAccountDeletionGoogle(context);
      }
    } else {
      // Email/password user — ask for password
      final passwordController = TextEditingController();
      final password = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This action is permanent and cannot be undone. '
                    'All your data will be deleted, including your wellness plans, '
                    'check-in history, journal entries, intentions, and uploaded files.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Enter your password to confirm',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(passwordController.text),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text(
                  'Delete My Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );

      if (password != null && password.isNotEmpty && mounted) {
        await _performAccountDeletionEmail(context, password);
      }
    }
  }

  Future<void> _performAccountDeletionGoogle(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isDeletingAccount = true;
    });

    final uid = user.uid;
    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final wellnessPlanState = Provider.of<WellnessPlanState>(context, listen: false);

    try {
      // Re-authenticate with Google
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await user.reauthenticateWithCredential(credential);

      // Delete Firestore data and Firebase Auth user
      await Future.any([
        () async {
          await _deleteAllUserData(uid);
          await user.delete();
        }(),
        Future.delayed(const Duration(seconds: 30)).then((_) {
          throw TimeoutException('Account deletion exceeded 30 seconds.');
        }),
      ]);

      // Clean up local state
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      checkInState.reset();
      wellnessPlanState.reset();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      WellnessPalSnackBar.show(context,
        message: 'Deletion timed out. Please try again.',
        icon: Icons.timer_off_rounded, isError: true,
        duration: const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      WellnessPalSnackBar.show(context,
        message: 'Failed to delete account. Please try again.',
        icon: Icons.error_outline_rounded, isError: true,
        duration: const Duration(seconds: 4));
    }
  }

  Future<void> _performAccountDeletionEmail(BuildContext context, String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WellnessPalSnackBar.show(
        context,
        message: 'No user signed in. Please sign in and try again.',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
      return;
    }

    setState(() {
      _isDeletingAccount = true;
    });

    final uid = user.uid;
    // Capture provider references before async operations that may unmount us
    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final wellnessPlanState = Provider.of<WellnessPlanState>(context, listen: false);

    try {
      // Re-authenticate the user so user.delete() won't fail with
      // 'requires-recent-login'.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      // Delete Firestore data and Firebase Auth user together.
      // user.delete() must happen while the user is still authenticated.
      await Future.any([
        () async {
          await _deleteAllUserData(uid);

          // Delete the Firebase Auth user IMMEDIATELY after Firestore data,
          // while the auth session is still fully valid.
          // This triggers sign-out on the auth stream automatically.
          await user.delete();
        }(),
        Future.delayed(const Duration(seconds: 30)).then((_) {
          throw TimeoutException('Account deletion exceeded 30 seconds.');
        }),
      ]);

      // Clear SharedPreferences and reset providers AFTER successful deletion.
      // user.delete() already triggered sign-out, but we still clean up
      // local state so the next user session starts fresh.
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      checkInState.reset();
      wellnessPlanState.reset();

      if (mounted) {
        // Navigate to the auth screen, clearing navigation stack.
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = false;
      });
      WellnessPalSnackBar.show(
        context,
        message: 'Deletion timed out. Please try again.',
        icon: Icons.timer_off_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = false;
      });
      final message = e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? 'Incorrect password. Please try again.'
          : 'Authentication failed. Please try again.';
      WellnessPalSnackBar.show(
        context,
        message: message,
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = false;
      });
      WellnessPalSnackBar.show(
        context,
        message: 'Failed to delete account. Please try again.',
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Deletes all Firestore documents under `users/{uid}/` and
  /// all Firebase Storage files belonging to the user.
  Future<void> _deleteAllUserData(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    // Define all subcollections to delete
    final subcollections = [
      'wellness_intentions',
      'daily_plans',
      'check_ins',
      'journal_entries',
      'travel_memories',
      'behavior_profile',
      'weekly_summaries',
    ];

    // Batch delete all subcollection documents
    WriteBatch batch = firestore.batch();
    int operationCount = 0;
    const batchLimit = 400; // Firestore batch max is 500; leave room

    for (final subcollection in subcollections) {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection(subcollection)
          .get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        operationCount++;

        // Commit in chunks if approaching batch limit
        if (operationCount >= batchLimit) {
          await batch.commit();
          batch = firestore.batch();
          operationCount = 0;
        }
      }
    }

    // Delete the user's root document
    batch.delete(firestore.collection('users').doc(uid));
    operationCount++;

    if (operationCount > 0) {
      await batch.commit();
    }

    // Delete all Firebase Storage files for the user
    try {
      final storageRef = storage.ref('travel-photos/$uid');
      final listResult = await storageRef.listAll();
      for (final item in listResult.items) {
        await item.delete();
      }
    } catch (e) {
      // Storage folder may not exist — that's fine
      debugPrint('Storage cleanup note: $e');
    }
  }
}


