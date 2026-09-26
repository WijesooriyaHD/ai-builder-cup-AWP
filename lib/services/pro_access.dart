/// A context-free snapshot of whether the user has Premium.
///
/// [AppState.isPro] is the source of truth, but reading it needs a
/// BuildContext. Several Life Toolkit features run their AI automatically when
/// a screen loads — sleep analysis, hydration coaching, calorie insights — from
/// inside a ChangeNotifier that has no context to read. Without something like
/// this, those calls could only be gated at the UI layer, which is exactly the
/// layer they bypass.
///
/// Kept deliberately dumb: a mirror, never a decision-maker. It is updated from
/// one place (the engagement binder, on every RevenueCat resolution) so it
/// cannot drift into being a second, competing definition of "is Premium".
///
/// Defaults to false. If a resolution has not happened yet, a feature is
/// treated as locked rather than unlocked — failing closed is the right way
/// round for a paywall.
class ProAccess {
  ProAccess._();

  static bool _isPro = false;

  /// Whether the user currently has Premium, as of the last resolution.
  static bool get isPro => _isPro;

  /// Called whenever RevenueCat resolves the user's tier.
  static void update(bool value) => _isPro = value;
}
