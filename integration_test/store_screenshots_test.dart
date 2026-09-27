// Drives the real app on a simulator to capture App Store screenshots.
// Prints "SHOT:<name>" markers; the host script captures the simulator
// screen (xcrun simctl io screenshot) when it sees one.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aiwellnesspal/features/nutrition/presentation/nutrition_coach_screen.dart';
import 'package:aiwellnesspal/features/sleep/presentation/sleep_coach_screen.dart';
import 'package:aiwellnesspal/main.dart' as app;
import 'package:aiwellnesspal/screens/main_wrapper.dart';
import 'package:aiwellnesspal/screens/wellness_pal_chat_screen.dart';
import 'package:aiwellnesspal/services/auth_service.dart';

const _email = String.fromEnvironment('DEMO_EMAIL');
const _password = String.fromEnvironment('DEMO_PASSWORD');
const _paywallOnly = bool.fromEnvironment('PAYWALL_ONLY');

Future<void> wait(WidgetTester t, [double seconds = 2]) async {
  final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> tapText(WidgetTester t, String text, {double after = 2}) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    debugPrint('DRIVER: text not found: $text');
    return false;
  }
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f.first, warnIfMissed: false);
  await wait(t, after);
  return true;
}

Future<bool> tapIcon(WidgetTester t, IconData icon, {double after = 2}) async {
  final f = find.byIcon(icon);
  if (f.evaluate().isEmpty) {
    debugPrint('DRIVER: icon not found: $icon');
    return false;
  }
  await t.tap(f.last, warnIfMissed: false);
  await wait(t, after);
  return true;
}

Future<void> shot(WidgetTester t, String name, [double settle = 3]) async {
  await wait(t, settle);
  // ignore: avoid_print
  print('SHOT:$name');
  await wait(t, 3); // host captures during this window
}

void dumpTexts(String label) {
  final texts = find.byType(Text).evaluate().map((e) {
    final w = e.widget as Text;
    return w.data ?? w.textSpan?.toPlainText() ?? '';
  }).where((s) => s.trim().isNotEmpty).take(60).join(' | ');
  debugPrint('DRIVER[$label] texts: $texts');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (t) async {
    app.main();
    await wait(t, 12);

    // Sign in (or create) the demo account directly, then let AuthWrapper route.
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await AuthService().signIn(email: _email, password: _password);
      } on FirebaseAuthException catch (e) {
        debugPrint('DRIVER: sign-in failed (${e.code}), creating account');
        await AuthService().signUp(
            email: _email, password: _password, displayName: 'Alex');
      }
    }
    await wait(t, 8);
    dumpTexts('after-auth');

    // One-time AI consent.
    if (find.text('I agree').evaluate().isNotEmpty) {
      await shot(t, '00_consent', 1);
      await tapText(t, 'I agree', after: 5);
    }

    // Onboarding.
    if (find.text('Get Started').evaluate().isNotEmpty) {
      await tapText(t, 'Get Started');
      final name = find.byType(TextField);
      if (name.evaluate().isNotEmpty) {
        await t.enterText(name.first, 'Alex');
        await wait(t, 1);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(t, 1);
      await tapText(t, 'Continue');
      await tapText(t, '25–34');
      await tapText(t, 'Continue');
      await tapText(t, 'Reduce Stress', after: 1);
      await tapText(t, 'Improve Sleep', after: 1);
      await tapText(t, 'Increase Energy', after: 1);
      await tapText(t, 'Continue');
      await tapText(t, 'Yoga', after: 1);
      await tapText(t, 'Walking', after: 1);
      await tapText(t, 'Meditation', after: 1);
      await tapText(t, 'Breathing Exercises', after: 1);
      await tapText(t, 'Continue');
      dumpTexts('onboarding-complete-step');
      await tapText(t, 'Complete', after: 20);
    }

    await wait(t, 10);

    if (_paywallOnly) {
      await tapIcon(t, Icons.settings_outlined, after: 4);
      if (await tapText(t, 'Upgrade to Premium', after: 10)) {
        await shot(t, '12_paywall', 4);
      }
      await wait(t, 3);
      return;
    }

    // Daily check-in (shown on first open of the day).
    if (find.text('Daily Check-In').evaluate().isNotEmpty) {
      await tapText(t, 'Good Energy', after: 1);
      await shot(t, '01_checkin', 1);
      await tapText(t, 'Next');
      await tapText(t, 'Calm', after: 1);
      await tapText(t, 'Next');
      await tapText(t, 'Well-Rested', after: 1);
      await tapText(t, '20–40 min', after: 1);
      dumpTexts('checkin-last');
      await tapText(t, 'Done', after: 30); // AI plan generation
    }
    await wait(t, 10);
    dumpTexts('home');
    await shot(t, '02_home');
    // Scroll home to show the plan.
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await t.drag(scrollable.first, const Offset(0, -900));
      await wait(t, 3);
      await shot(t, '03_home_plan');
      await t.drag(scrollable.first, const Offset(0, 900));
      await wait(t, 2);
    }

    Future<void> openScreen(Widget screen, String name, {double settle = 12}) async {
      final nav = Navigator.of(t.element(find.byType(MainWrapper, skipOffstage: false)));
      nav.push(MaterialPageRoute(builder: (_) => screen));
      await wait(t, settle);
      dumpTexts(name);
      await shot(t, name, 1);
    }

    // Pal chat with a real AI reply.
    await openScreen(const WellnessPalChatScreen(), '04_pal_chat_empty', settle: 4);
    final input = find.byType(TextField);
    if (input.evaluate().isNotEmpty) {
      await t.enterText(input.last, "I've been really stressed with work this week");
      await wait(t, 1);
      await t.testTextInput.receiveAction(TextInputAction.send);
      await wait(t, 25);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(t, 2);
      dumpTexts('pal-chat');
      await shot(t, '05_pal_chat', 1);
    }
    Navigator.of(t.element(find.byType(MainWrapper, skipOffstage: false))).pop();
    await wait(t, 3);

    await openScreen(const NutritionCoachScreen(), '06_nutrition');
    Navigator.of(t.element(find.byType(MainWrapper, skipOffstage: false))).pop();
    await wait(t, 3);

    await openScreen(const SleepCoachScreen(), '07_sleep', settle: 20);
    Navigator.of(t.element(find.byType(MainWrapper, skipOffstage: false))).pop();
    await wait(t, 3);

    // Tabs.
    await tapIcon(t, Icons.self_improvement_outlined, after: 4);
    dumpTexts('tab-intentions');
    await shot(t, '08_intentions');
    await tapIcon(t, Icons.checklist_rounded, after: 4);
    dumpTexts('tab-habits');
    await shot(t, '09_habits');
    await tapIcon(t, Icons.menu_book_outlined, after: 4);
    dumpTexts('tab-reflection');
    await shot(t, '10_reflection');
    await tapIcon(t, Icons.settings_outlined, after: 4);
    dumpTexts('tab-settings');
    await shot(t, '11_settings');

    // Paywall (native RevenueCat UI — the host capture sees it).
    if (await tapText(t, 'Upgrade to Premium', after: 8)) {
      await shot(t, '12_paywall', 4);
    }
    await wait(t, 3);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
