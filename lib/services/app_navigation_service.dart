import 'package:flutter/foundation.dart';

/// The five bottom-navigation tabs of [MainWrapper], in order.
enum AppTab {
  home,
  intentions,
  habitBuilder,
  reflection,
  settings,
}

extension AppTabIndex on AppTab {
  int get index {
    switch (this) {
      case AppTab.home:
        return 0;
      case AppTab.intentions:
        return 1;
      case AppTab.habitBuilder:
        return 2;
      case AppTab.reflection:
        return 3;
      case AppTab.settings:
        return 4;
    }
  }
}

/// A lightweight app-wide navigation bus.
///
/// Lets any part of the app (e.g. the voice assistant, running inside a modal
/// bottom sheet) request a bottom-tab switch without holding a reference to
/// [MainWrapper]. [MainWrapper] listens and reacts.
class AppNavigationService extends ChangeNotifier {
  int _requestedIndex = 0;
  int get requestedIndex => _requestedIndex;

  /// Requests a switch to [tab]. Always notifies (even for the same tab) so a
  /// repeated voice command re-triggers the listener.
  void goToTab(AppTab tab) {
    _requestedIndex = tab.index;
    notifyListeners();
  }

  /// Requests a switch to a raw tab index (0-4).
  void goToIndex(int index) {
    _requestedIndex = index.clamp(0, 4);
    notifyListeners();
  }
}
