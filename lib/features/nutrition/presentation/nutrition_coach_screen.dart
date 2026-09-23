import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../widgets/ai_wellness_loader.dart';
import '../../../widgets/add_to_home_wrapper.dart';
import '../../../services/home_tool_cards_service.dart';
import '../domain/nutrition_analysis_service.dart';
import '../domain/nutrition_models.dart';
import 'barcode_scanner_screen.dart';
import 'nutrition_state.dart';
import 'widgets/nutrition_cards.dart';

/// The AI Nutrition Coach home: a dashboard of today's progress and coaching,
/// a food diary grouped by meal type, and entry points to analyze meals via
/// photo, text, or barcode.
class NutritionCoachScreen extends StatefulWidget {
  const NutritionCoachScreen({super.key});

  @override
  State<NutritionCoachScreen> createState() => _NutritionCoachScreenState();
}

class _NutritionCoachScreenState extends State<NutritionCoachScreen> {
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NutritionState>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<NutritionState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFF2F8F5),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Nutrition Coach'),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Daily goals',
                icon: const Icon(Icons.flag_rounded),
                onPressed: () => _showGoalsSheet(context, state),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: kNutritionAccent,
            foregroundColor: Colors.white,
            onPressed: () => _showAddMealSheet(context, state),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add meal'),
          ),
          body: RefreshIndicator(
            onRefresh: () => state.load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                AddToHomeWrapper(
                  toolCardId: HomeToolCard.nutrition,
                  child: DailyProgressCard(
                      totals: state.todaysTotals, goals: state.goals),
                ),
                const SizedBox(height: 16),
                AddToHomeWrapper(
                  toolCardId: HomeToolCard.nutritionCoach,
                  child: _buildCoachCard(context, state),
                ),
                const SizedBox(height: 16),
                if (state.recentMeals().isNotEmpty) ...[
                  AddToHomeWrapper(
                    toolCardId: HomeToolCard.nutritionRecentMeals,
                    child: RecentMealsCard(
                      meals: state.recentMeals(),
                      onTapMeal: (m) => _showMealDetail(context, state, m),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildDiary(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Coach feedback card
  // ---------------------------------------------------------------------------
  Widget _buildCoachCard(BuildContext context, NutritionState state) {
    final theme = Theme.of(context);
    final feedback = state.dailyFeedback;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kNutritionAccent.withOpacity(0.18),
            kNutritionAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kNutritionAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  color: kNutritionAccent, size: 22),
              const SizedBox(width: 8),
              Text('Coach insights',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ...feedback.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle,
                        size: 6, color: kNutritionAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Diary grouped by meal type
  // ---------------------------------------------------------------------------
  Widget _buildDiary(BuildContext context, NutritionState state) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Food diary',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Today',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...MealType.values.map((type) => _diarySection(context, state, type)),
        ],
      ),
    );
  }

  Widget _diarySection(
      BuildContext context, NutritionState state, MealType type) {
    final theme = Theme.of(context);
    final meals = state.mealsOfType(type);
    final cals = meals.fold<int>(0, (s, m) => s + m.calories);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(type.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(type.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$cals kcal',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: kNutritionAccent, size: 20),
                onPressed: () =>
                    _showAddMealSheet(context, state, presetType: type),
              ),
            ],
          ),
          if (meals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 4),
              child: Text('Nothing logged',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withOpacity(0.6))),
            )
          else
            ...meals.map((m) => _diaryRow(context, state, m)),
        ],
      ),
    );
  }

  Widget _diaryRow(BuildContext context, NutritionState state, Meal m) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE9506E).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: Color(0xFFE9506E)),
      ),
      onDismissed: (_) => state.deleteMeal(m.id),
      child: InkWell(
        onTap: () => _showMealDetail(context, state, m),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: Text(m.mealName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
              ),
              Text('${m.calories} kcal',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Add meal — choose input method
  // ---------------------------------------------------------------------------
  void _showAddMealSheet(BuildContext context, NutritionState state,
      {MealType? presetType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetContainer(
        title: 'Add a meal',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _methodTile(ctx, Icons.photo_camera_rounded, 'Take a photo',
                'Snap your plate for instant analysis', () {
              Navigator.pop(ctx);
              _analyzeFromImage(context, state, ImageSource.camera, presetType);
            }),
            _methodTile(ctx, Icons.photo_library_rounded, 'Choose from gallery',
                'Analyze a saved food photo', () {
              Navigator.pop(ctx);
              _analyzeFromImage(
                  context, state, ImageSource.gallery, presetType);
            }),
            _methodTile(ctx, Icons.edit_note_rounded, 'Describe it',
                'e.g. "2 egg hoppers and milk tea"', () {
              Navigator.pop(ctx);
              _analyzeFromText(context, state, presetType);
            }),
            _methodTile(ctx, Icons.qr_code_scanner_rounded, 'Scan a barcode',
                'Look up a packaged product', () {
              Navigator.pop(ctx);
              _analyzeFromBarcode(context, state, presetType);
            }),
          ],
        ),
      ),
    );
  }

  Widget _methodTile(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kNutritionAccent.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: kNutritionAccent),
      ),
      title: Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }

  // ---------------------------------------------------------------------------
  // Input flows
  // ---------------------------------------------------------------------------
  Future<void> _analyzeFromImage(BuildContext context, NutritionState state,
      ImageSource source, MealType? presetType) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (picked == null) return;
      final file = File(picked.path);
      if (!context.mounted) return;
      _showAnalyzingDialog(context);
      final result = await state.analyzePhoto(file);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (result != null && context.mounted) {
        _showReviewSheet(context, state, result,
            presetType: presetType, imageFile: file);
      } else if (context.mounted) {
        _snack(context, state.error ?? 'Could not analyze the photo.');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        _snack(context, 'Could not open the camera or gallery.');
      }
    }
  }

  void _analyzeFromText(
      BuildContext context, NutritionState state, MealType? presetType) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _SheetContainer(
          title: 'Describe your meal',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. Chicken fried rice and a glass of juice',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNutritionAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  _showAnalyzingDialog(context);
                  final result = await state.analyzeText(text);
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                  if (result != null && context.mounted) {
                    _showReviewSheet(context, state, result,
                        presetType: presetType);
                  } else if (context.mounted) {
                    _snack(context, state.error ?? 'Could not analyze that.');
                  }
                },
                child: const Text('Analyze with AI'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the live camera scanner. On a successful scan, runs the Open Food
  /// Facts lookup; if the user taps "manual", falls back to typing the number.
  Future<void> _analyzeFromBarcode(
      BuildContext context, NutritionState state, MealType? presetType) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (!context.mounted || result == null) return;

    if (result == '__manual__') {
      _manualBarcodeEntry(context, state, presetType);
      return;
    }
    await _lookupBarcode(context, state, result, presetType);
  }

  /// Runs the OFF lookup for [code] with the analyzing dialog and result sheet,
  /// falling back to the not-found sheet on [BarcodeNotFoundException].
  Future<void> _lookupBarcode(BuildContext context, NutritionState state,
      String code, MealType? presetType) async {
    _showAnalyzingDialog(context);
    try {
      final result = await state.analyzeBarcode(code);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (result != null && context.mounted) {
        _showReviewSheet(context, state, result, presetType: presetType);
      }
    } on BarcodeNotFoundException {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showBarcodeNotFound(context, state, code, presetType);
      }
    }
  }

  void _manualBarcodeEntry(
      BuildContext context, NutritionState state, MealType? presetType) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _SheetContainer(
          title: 'Enter barcode',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the product barcode number to look it up in the '
                'Open Food Facts database.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 737628064502',
                  prefixIcon: const Icon(Icons.qr_code_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNutritionAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final code = controller.text.trim();
                  if (code.isEmpty) return;
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  await _lookupBarcode(context, state, code, presetType);
                },
                child: const Text('Look up product'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBarcodeNotFound(BuildContext context, NutritionState state,
      String code, MealType? presetType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetContainer(
        title: 'Product not found',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We couldn\'t find $code in Open Food Facts. You can describe '
              'the product and let AI estimate it, or re-enter the number.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _methodTile(ctx, Icons.auto_awesome_rounded, 'Describe & estimate',
                'Type what it is for an AI estimate', () {
              Navigator.pop(ctx);
              _analyzeFromText(context, state, presetType);
            }),
            _methodTile(ctx, Icons.keyboard_rounded, 'Enter number again',
                'Re-type the barcode number', () {
              Navigator.pop(ctx);
              _manualBarcodeEntry(context, state, presetType);
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Review + save
  // ---------------------------------------------------------------------------
  void _showReviewSheet(
    BuildContext context,
    NutritionState state,
    NutritionResult result, {
    MealType? presetType,
    File? imageFile,
  }) {
    MealType selected = presetType ?? MealTypeInfo.forNow();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return _SheetContainer(
            title: result.mealName,
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (result.servingInfo != null &&
                    result.servingInfo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(result.servingInfo!,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ),
                NutritionSummaryCard(
                  title: 'Estimated nutrition',
                  calories: result.calories,
                  macros: result.macros,
                ),
                const SizedBox(height: 12),
                FoodQualityCard(
                  score: result.foodQualityScore,
                  insights: result.aiInsights,
                ),
                const SizedBox(height: 16),
                Text('Add to',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: MealType.values.map((t) {
                    final sel = t == selected;
                    return ChoiceChip(
                      label: Text('${t.emoji} ${t.label}'),
                      selected: sel,
                      selectedColor: kNutritionAccent.withOpacity(0.2),
                      onSelected: (_) => setLocal(() => selected = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNutritionAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: saving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.check_rounded),
                  label: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Log this meal'),
                  onPressed: saving
                      ? null
                      : () async {
                          setLocal(() => saving = true);
                          await state.logMeal(result,
                              mealType: selected, imageFile: imageFile);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            _snack(context, 'Meal logged.');
                          }
                        },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Meal detail
  // ---------------------------------------------------------------------------
  void _showMealDetail(BuildContext context, NutritionState state, Meal m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetContainer(
        title: m.mealName,
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(m.imageUrl!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            NutritionSummaryCard(
                title: '${m.mealType.label} · nutrition',
                calories: m.calories,
                macros: m.macros),
            const SizedBox(height: 12),
            FoodQualityCard(score: m.foodQualityScore, insights: m.aiInsights),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFE9506E)),
              label: const Text('Delete meal',
                  style: TextStyle(color: Color(0xFFE9506E))),
              onPressed: () {
                state.deleteMeal(m.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Goals sheet
  // ---------------------------------------------------------------------------
  void _showGoalsSheet(BuildContext context, NutritionState state) {
    final cal = TextEditingController(text: '${state.goals.calories}');
    final pro = TextEditingController(text: '${state.goals.protein}');
    final carb = TextEditingController(text: '${state.goals.carbs}');
    final fat = TextEditingController(text: '${state.goals.fat}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _SheetContainer(
          title: 'Daily goals',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _goalField(cal, 'Calories', 'kcal'),
              _goalField(pro, 'Protein', 'g'),
              _goalField(carb, 'Carbs', 'g'),
              _goalField(fat, 'Fat', 'g'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNutritionAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    state.updateGoals(NutritionGoals(
                      calories: int.tryParse(cal.text) ?? state.goals.calories,
                      protein: int.tryParse(pro.text) ?? state.goals.protein,
                      carbs: int.tryParse(carb.text) ?? state.goals.carbs,
                      fat: int.tryParse(fat.text) ?? state.goals.fat,
                      sugar: state.goals.sugar,
                    ));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save goals'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalField(
      TextEditingController controller, String label, String unit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared UI helpers
  // ---------------------------------------------------------------------------
  void _showAnalyzingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Same AI + wellness animation used when generating wellness
              // intentions and meal plans.
              const AiWellnessLoader(color: kNutritionAccent, size: 160),
              const SizedBox(height: 20),
              Text(
                'Analyzing your meal…',
                style: Theme.of(dialogContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'AI is estimating the calories and macros from your description.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

/// A rounded bottom-sheet container with a grab handle and title.
class _SheetContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final bool scrollable;

  const _SheetContainer({
    required this.title,
    required this.child,
    this.scrollable = false,
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
      child: scrollable
          ? SingleChildScrollView(child: content)
          : content,
    );
  }
}
