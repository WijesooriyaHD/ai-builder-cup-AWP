import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/home_tool_cards_service.dart';
import '../utils/wellnesspal_snackbar.dart';

/// Wraps a wellness-tool summary card so a long-press offers to add it to (or
/// remove it from) the Home screen.
///
/// The actual enabled/disabled state lives in [HomeToolCardsService] (persisted
/// locally + mirrored to Firestore), so a card added here shows up on Home with
/// the same pin-to-top / re-arrange abilities as the default Home cards.
class AddToHomeWrapper extends StatelessWidget {
  const AddToHomeWrapper({
    super.key,
    required this.toolCardId,
    required this.child,
  });

  /// One of the [HomeToolCard] ids.
  final String toolCardId;

  /// The tool's summary card widget.
  final Widget child;

  void _showSheet(BuildContext context) {
    final service = context.read<HomeToolCardsService>();
    final isOnHome = service.isEnabled(toolCardId);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
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
                  HomeToolCard.titleFor(toolCardId),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
            if (isOnHome)
              ListTile(
                leading: Icon(Icons.remove_circle_outline_rounded,
                    color: theme.colorScheme.error),
                title: const Text('Remove from Home'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await service.remove(toolCardId);
                  if (context.mounted) {
                    WellnessPalSnackBar.show(
                      context,
                      message: 'Removed from Home',
                      icon: Icons.home_outlined,
                    );
                  }
                },
              )
            else
              ListTile(
                leading: Icon(Icons.add_to_home_screen_rounded,
                    color: theme.colorScheme.primary),
                title: const Text('Add to Home Screen'),
                subtitle: const Text(
                    'Show this card on your Home screen. You can then pin or '
                    're-arrange it there.'),
                isThreeLine: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  await service.add(toolCardId);
                  if (context.mounted) {
                    WellnessPalSnackBar.show(
                      context,
                      message: 'Added to Home',
                      icon: Icons.check_circle_rounded,
                      iconColor: Colors.green,
                    );
                  }
                },
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // translucent so any inner tap targets on the card still work while a
      // long-press opens the add/remove sheet.
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _showSheet(context),
      child: child,
    );
  }
}
