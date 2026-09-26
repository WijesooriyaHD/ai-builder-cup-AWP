import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import 'achievement_completion_page.dart';
import '../utils/pro_modal_utils.dart';
import '../widgets/ai_wellness_loader.dart';

import '../data/dream_templates.dart';
import '../utils/icon_resolver.dart';

class AddDreamScreen extends StatefulWidget {
  final DreamTemplate? template;
  const AddDreamScreen({super.key, this.template});

  @override
  State<AddDreamScreen> createState() => _AddDreamScreenState();
}

class _AddDreamScreenState extends State<AddDreamScreen> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;
  late int _selectedColor;
  late int _selectedIcon;
  DreamTemplate? _selectedTemplate;
  
  bool _generateWithAi = false;
  int _aiDurationDays = 7;
  bool _isGenerating = false;
  bool _iconSectionExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.template?.title ?? '');
    // Default to the first wellness icon + its paired color when no template.
    _selectedColor = widget.template?.color ?? _icons.first.color;
    _selectedIcon =
        widget.template?.icon.codePoint ?? _icons.first.icon.codePoint;
    _selectedTemplate = widget.template;
  }

  // Wellness-focused icon set. Each icon carries its own "vibe" color, so
  // picking an icon also sets the intention's theme color. Each icon must have
  // a matching case in resolveIconData() so it renders on the intention cards.
  final List<_WellnessIconOption> _icons = const [
    _WellnessIconOption(Icons.self_improvement_rounded, 0xFF9C27B0), // Meditation
    _WellnessIconOption(Icons.spa_rounded, 0xFF009688), // Self-care
    _WellnessIconOption(Icons.favorite_rounded, 0xFFE91E63), // Heart health
    _WellnessIconOption(Icons.fitness_center_rounded, 0xFFFF5722), // Strength
    _WellnessIconOption(Icons.directions_run_rounded, 0xFFFF9800), // Movement
    _WellnessIconOption(Icons.bedtime_rounded, 0xFF3F51B5), // Sleep
    _WellnessIconOption(Icons.restaurant_rounded, 0xFF8BC34A), // Nutrition
    _WellnessIconOption(Icons.local_drink_rounded, 0xFF03A9F4), // Hydration
    _WellnessIconOption(Icons.psychology_rounded, 0xFF673AB7), // Mindset
    _WellnessIconOption(Icons.air_rounded, 0xFF00BCD4), // Breathwork
    _WellnessIconOption(Icons.wb_sunny_rounded, 0xFFFFC107), // Energy
    _WellnessIconOption(Icons.filter_vintage_rounded, 0xFF4CAF50), // Growth
  ];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(_selectedColor);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("New Wellness Intention"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Live preview header -------------------------------------
              _buildPreviewHeader(theme, accent),
              const SizedBox(height: 28),

              // ---- Quick-start templates -----------------------------------
              _buildSectionLabel(theme, Icons.auto_awesome_rounded, "Quick start"),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: dreamTemplates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final template = dreamTemplates[index];
                    final selected = _selectedTemplate == template;
                    return ActionChip(
                      avatar: Icon(template.icon,
                          size: 18, color: Color(template.color)),
                      label: Text(template.title),
                      labelStyle: TextStyle(
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                        color: selected
                            ? Color(template.color)
                            : theme.colorScheme.onSurface,
                      ),
                      onPressed: () {
                        setState(() {
                          _controller.text = template.title;
                          _selectedColor = template.color;
                          _selectedIcon = template.icon.codePoint;
                          _selectedTemplate = template;
                        });
                      },
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      backgroundColor: Color(template.color)
                          .withOpacity(selected ? 0.16 : 0.05),
                      side: BorderSide(
                          color: Color(template.color)
                              .withOpacity(selected ? 0.5 : 0.2)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // ---- Intention name ------------------------------------------
              _buildSectionLabel(
                  theme, Icons.edit_note_rounded, "What's your intention?"),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.25)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextFormField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    hintText: "e.g. Learn Yoga...",
                    border: InputBorder.none,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a wellness intention';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 28),

              // ---- Icon + vibe (collapsible) -------------------------------
              _buildIconSection(theme, accent),
              const SizedBox(height: 28),

              // ---- AI plan generation --------------------------------------
              _buildAiCard(theme, accent),
              const SizedBox(height: 20),

              // ---- Target date (hidden when AI is on) ----------------------
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _generateWithAi
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel(theme, Icons.event_rounded,
                        "Target date (optional)"),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.4),
                          border: Border.all(color: accent.withOpacity(0.25)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                color: accent, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              _selectedDate == null
                                  ? "Set a deadline"
                                  : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedDate == null
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.onSurface),
                            ),
                            const Spacer(),
                            if (_selectedDate != null)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedDate = null),
                                child: Icon(Icons.close_rounded,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  onPressed: _isGenerating ? null : _saveDream,
                  icon: _isGenerating
                      ? const SizedBox.shrink()
                      : Icon(_generateWithAi
                          ? Icons.auto_awesome_rounded
                          : Icons.check_circle_rounded),
                  label: _isGenerating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          _generateWithAi
                              ? "Generate My Plan"
                              : "Set My Intention",
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small labelled section header with a leading icon.
  Widget _buildSectionLabel(ThemeData theme, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Collapsible "Choose an icon" section. Header shows the current selection
  /// and a rotating chevron; the icon grid expands/collapses on tap.
  Widget _buildIconSection(ThemeData theme, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(
              () => _iconSectionExpanded = !_iconSectionExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.emoji_emotions_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  "Choose an icon (optional)",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Preview of current selection when collapsed.
                if (!_iconSectionExpanded)
                  Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withOpacity(0.5)),
                    ),
                    child: Icon(resolveIconData(_selectedIcon),
                        size: 18, color: accent),
                  ),
                AnimatedRotation(
                  turns: _iconSectionExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _iconSectionExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _icons.map((option) {
                final optionColor = Color(option.color);
                final selected = _selectedIcon == option.icon.codePoint;
                return GestureDetector(
                  // Selecting an icon also sets the intention's vibe color.
                  onTap: () => setState(() {
                    _selectedIcon = option.icon.codePoint;
                    _selectedColor = option.color;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: optionColor.withOpacity(selected ? 0.9 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: optionColor.withOpacity(0.45),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                      border: Border.all(
                        color: selected
                            ? optionColor
                            : optionColor.withOpacity(0.35),
                        width: 2,
                      ),
                    ),
                    child: Icon(option.icon,
                        color: selected ? Colors.white : optionColor),
                  ),
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Live preview of how the intention will look, updating as the user edits.
  Widget _buildPreviewHeader(ThemeData theme, Color accent) {
    final title = _controller.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.18), accent.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(resolveIconData(_selectedIcon),
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "YOUR INTENTION",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title.isEmpty ? "Choose your focus…" : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: title.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// AI plan-generation card with toggle + duration selector.
  Widget _buildAiCard(ThemeData theme, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: _generateWithAi
            ? accent.withOpacity(0.06)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _generateWithAi
              ? accent.withOpacity(0.4)
              : theme.dividerColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _generateWithAi,
            onChanged: (val) {
              // Turning it ON is the Premium action; turning it off is always
              // allowed, so a user who lapses is never stuck with it enabled.
              if (val &&
                  !ProModalUtils.requirePro(
                    context,
                    title: 'AI plans are Premium',
                    message:
                        'Upgrade to have your pal break this intention into '
                        'gentle daily wellness steps.',
                  )) {
                return;
              }
              setState(() {
                _generateWithAi = val;
                if (val) _selectedDate = null;
              });
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text("Generate plan with AI",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text("Break it into gentle daily wellness steps"),
            ),
            activeThumbColor: accent,
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _generateWithAi
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: [
                Divider(height: 1, color: theme.dividerColor.withOpacity(0.3)),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text("Duration",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: theme.dividerColor.withOpacity(0.4)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            dropdownColor: theme.colorScheme.surface,
                            value: _aiDurationDays,
                            borderRadius: BorderRadius.circular(12),
                            items: const [
                              DropdownMenuItem(
                                  value: 7,
                                  child: Text("7 Days (Kickstarter)")),
                              DropdownMenuItem(
                                  value: 14, child: Text("14 Days (Sprint)")),
                              DropdownMenuItem(
                                  value: 30,
                                  child: Text("30 Days (Challenge)")),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _aiDurationDays = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveDream() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isGenerating = true);
      
      // Show loading bottom sheet if AI is enabled
      if (_generateWithAi && mounted) {
        _showAiLoadingBottomSheet(context);
      }

      try {
        final appState = Provider.of<AppState>(context, listen: false);
        
        // Check for Pro limit: 3 dreams max for free users
        if (!appState.isPro && appState.dreams.length >= 3) {
          if (_generateWithAi && mounted) Navigator.pop(context);
          setState(() => _isGenerating = false);
          ProModalUtils.showProLimitModal(context);
          return;
        }

        List<Map<String, dynamic>>? aiSteps;

        // Generate task steps via Firebase AI (Vertex, Gemini Flash).
        if (_generateWithAi) {
           try {
             aiSteps = await AIService().generateDreamTasks(
               dream: _controller.text,
               days: _aiDurationDays,
             );
           } catch (e) {
             debugPrint("AI Generation Failed: $e");
             if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("AI Generation failed: $e. Creating empty dream instead."))
                );
             }
           }
        }

        final newAchievements = await appState.addDream(
            _controller.text, 
            deadline: _generateWithAi 
                ? DateTime.now().add(Duration(days: _aiDurationDays)) 
                : _selectedDate,
            themeColor: _selectedColor,
            themeIcon: _selectedIcon,
            initialSteps: aiSteps ?? _selectedTemplate?.steps, 
        );
        
        if (mounted) {
          // If loading sheet was shown, pop it
          if (_generateWithAi) {
            Navigator.pop(context);
          }
          
          Navigator.pop(context);
          
          if (newAchievements.isNotEmpty) {
             for (final achievement in newAchievements) {
                 Navigator.of(context).push(
                   MaterialPageRoute(
                     builder: (context) => AchievementCompletionPage(achievement: achievement),
                     fullscreenDialog: true,
                   ),
                 );
                if (newAchievements.length > 1) {
                  await Future.delayed(const Duration(seconds: 2));
                }
             }
          }
        }
      } catch (e) {
        if (mounted && _generateWithAi) {
          Navigator.pop(context);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"))
          );
        }
      } finally {
        if (mounted) setState(() => _isGenerating = false);
      }
    }
  }

  void _showAiLoadingBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _AiLoadingBottomSheetContent(selectedColor: _selectedColor),
    );
  }
}

class _AiLoadingBottomSheetContent extends StatefulWidget {
  final int selectedColor;
  const _AiLoadingBottomSheetContent({required this.selectedColor});

  @override
  State<_AiLoadingBottomSheetContent> createState() => _AiLoadingBottomSheetContentState();
}

class _AiLoadingBottomSheetContentState
    extends State<_AiLoadingBottomSheetContent> {
  @override
  Widget build(BuildContext context) {
    final color = Color(widget.selectedColor);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          AiWellnessLoader(color: color, size: 180),
          const SizedBox(height: 20),
          Text(
            "Shaping your wellness journey...",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            "AI is mapping out your path and breaking it down into gentle daily steps.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}



/// An icon paired with its "vibe" theme color. Picking the icon also applies
/// its color as the intention's theme color.
class _WellnessIconOption {
  final IconData icon;
  final int color;
  const _WellnessIconOption(this.icon, this.color);
}
