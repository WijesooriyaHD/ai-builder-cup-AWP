import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/wellnesspal_snackbar.dart';

/// Small print shown under AI-generated content, making clear it is not
/// medical advice (App Store Review Guideline 1.4.1).
class AiDisclaimerNote extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const AiDisclaimerNote({
    super.key,
    this.text = "Wellness Pal is an AI and can make mistakes. It isn't medical "
        'advice. For health concerns, talk to a qualified professional.',
    this.padding = const EdgeInsets.fromLTRB(24, 4, 24, 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, height: 1.35, color: Colors.grey.shade500),
      ),
    );
  }
}

/// Lets users flag an AI response as harmful, inaccurate or inappropriate
/// (App Store Review Guideline 1.2). Reports are written to
/// `users/{uid}/ai_reports`, which the owner-scoped Firestore rules cover and
/// account deletion removes.
class AiResponseReporter {
  AiResponseReporter._();

  static const List<String> _reasons = [
    'Harmful or unsafe advice',
    'Inaccurate information',
    'Offensive or inappropriate',
    'Something else',
  ];

  static Future<void> showReportSheet(
    BuildContext context, {
    required String responseText,
    required String source,
  }) async {
    final theme = Theme.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? theme.cardColor
              : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Report this response',
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                "What's wrong with it?",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              ..._reasons.map((r) => ListTile(
                    title: Text(r),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(sheetContext, r),
                  )),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );

    if (reason == null || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('ai_reports')
            .add({
          'reason': reason,
          'source': source,
          'responseText': responseText,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (!context.mounted) return;
      WellnessPalSnackBar.show(context,
          message: 'Thanks. We\'ll review this response.',
          icon: Icons.flag_rounded);
    } catch (e) {
      debugPrint('❌ AI report failed: $e');
      if (!context.mounted) return;
      WellnessPalSnackBar.show(context,
          message: 'Could not send report. Please try again.',
          isError: true);
    }
  }
}
