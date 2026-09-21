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

  /// Sub-tab within the Home screen's inner switcher: 0 = "Home", 1 = "More"
  /// (Life Toolkit entry + Wellness Reads). Lets the voice pal open Wellness
  /// Reads, which is a sub-tab rather than its own route.
  int _requestedHomeSubTab = 0;
  int get requestedHomeSubTab => _requestedHomeSubTab;

  /// Incremented on every [goToHomeSubTab] call so a repeated request for the
  /// SAME sub-tab still re-triggers listeners (matching [goToTab]'s behavior).
  int _homeSubTabRequestId = 0;
  int get homeSubTabRequestId => _homeSubTabRequestId;

  /// Requests the Home screen's inner sub-tab ([index] 0 = Home, 1 = More).
  /// Also switches the bottom nav to Home so the sub-tab is actually visible.
  void goToHomeSubTab(int index) {
    _requestedHomeSubTab = index.clamp(0, 1);
    _homeSubTabRequestId++;
    _requestedIndex = AppTab.home.index;
    notifyListeners();
  }

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
