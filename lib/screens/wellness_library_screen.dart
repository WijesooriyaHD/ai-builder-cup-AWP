import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../widgets/frosted_container.dart';
import 'short_read_screen.dart';
import 'audio_session_screen.dart';
import 'guided_reflection_screen.dart';

/// A content item in the Wellness Library.
class WellnessLibraryItem {
  final String id;
  final String title;
  final String category;
  final String format; // 'short_read', 'audio', 'guided_reflection'
  final int durationMinutes;
  final bool isFree;
  final String description;
  final List<WellnessCategory> relatedCategories;

  const WellnessLibraryItem({
    required this.id,
    required this.title,
    required this.category,
    required this.format,
    required this.durationMinutes,
    required this.isFree,
    required this.description,
    this.relatedCategories = const [],
  });

  /// Display label for the format type.
  String get formatLabel {
    switch (format) {
      case 'audio':
        return 'Audio';
      case 'guided_reflection':
        return 'Guided Reflection';
      default:
        return 'Short Read';
    }
  }

  /// Icon for the format type.
  IconData get formatIcon {
    switch (format) {
      case 'audio':
        return Icons.headphones_rounded;
      case 'guided_reflection':
        return Icons.edit_note_rounded;
      default:
        return Icons.article_rounded;
    }
  }
}

/// Wellness Library screen replacing the Reading Library / Blog screens.
///
/// Provides 5 topic category tabs plus a "Saved" tab. Each tab shows content
/// items as frosted-glass cards. A "Recommended" section appears at the top
/// when user intentions or recent check-in categories match content items.
///
/// Requirements: 7.1, 7.7, 7.8, 7.9, 7.10
class WellnessLibraryScreen extends StatefulWidget {
  const WellnessLibraryScreen({super.key});

  @override
  State<WellnessLibraryScreen> createState() => _WellnessLibraryScreenState();
}

class _WellnessLibraryScreenState extends State<WellnessLibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _categories = [
    'Recovery Education',
    'Stress Management',
    'Sleep Improvement',
    'Pilates Guidance',
    "Women's Wellness",
  ];

  static const Map<String, IconData> _categoryIcons = {
    'Recovery Education': Icons.healing_rounded,
    'Stress Management': Icons.spa_rounded,
    'Sleep Improvement': Icons.bedtime_rounded,
    'Pilates Guidance': Icons.fitness_center_rounded,
    "Women's Wellness": Icons.favorite_rounded,
  };

  /// Maps library categories to WellnessCategory enums for recommendation matching.
  static const Map<String, List<WellnessCategory>> _categoryToWellnessCategories = {
    'Recovery Education': [WellnessCategory.recovery, WellnessCategory.energy],
    'Stress Management': [WellnessCategory.stress, WellnessCategory.mindfulness],
    'Sleep Improvement': [WellnessCategory.sleep],
    'Pilates Guidance': [WellnessCategory.flexibility, WellnessCategory.movement],
    "Women's Wellness": [WellnessCategory.general, WellnessCategory.mentalClarity],
  };

  /// Maps MoodState to relevant library categories for recommendation.
  static const Map<MoodState, List<String>> _moodToCategoryMap = {
    MoodState.stressed: ['Stress Management', 'Sleep Improvement'],
    MoodState.anxious: ['Stress Management', "Women's Wellness"],
    MoodState.tired: ['Sleep Improvement', 'Recovery Education'],
    MoodState.calm: ['Pilates Guidance', "Women's Wellness"],
    MoodState.energized: ['Pilates Guidance', 'Recovery Education'],
    MoodState.content: ["Women's Wellness", 'Pilates Guidance'],
  };

  late Map<String, List<WellnessLibraryItem>> _itemsByCategory;
  Set<String> _bookmarkedItemIds = {};
  Map<String, DateTime> _bookmarkDates = {};
  bool _isLoadingBookmarks = true;

  @override
  void initState() {
    super.initState();
    // 5 categories + 1 Saved tab = 6 tabs
    _tabController = TabController(length: _categories.length + 1, vsync: this);
    _itemsByCategory = _buildLibraryItems();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Loads bookmarks from SharedPreferences and Firestore.
  Future<void> _loadBookmarks() async {
    try {
      // Load from local cache first
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('wellness_library_bookmarks');
      if (raw != null) {
        final Map<String, dynamic> decoded =
            jsonDecode(raw) as Map<String, dynamic>;
        _bookmarkedItemIds = decoded.keys.toSet();
        _bookmarkDates = decoded.map(
          (key, value) => MapEntry(key, DateTime.parse(value as String)),
        );
      }

      // Also try Firestore for authoritative data
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('wellness_library_bookmarks')
            .orderBy('bookmarkedAt', descending: true)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final ids = <String>{};
          final dates = <String, DateTime>{};
          for (final doc in snapshot.docs) {
            ids.add(doc.id);
            final ts = doc.data()['bookmarkedAt'];
            if (ts is Timestamp) {
              dates[doc.id] = ts.toDate();
            } else {
              dates[doc.id] = DateTime.now();
            }
          }
          _bookmarkedItemIds = ids;
          _bookmarkDates = dates;
          await _saveBookmarksLocally();
        }
      }
    } catch (e) {
      debugPrint('WellnessLibrary: failed to load bookmarks: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingBookmarks = false);
      }
    }
  }

  /// Persists bookmarks to SharedPreferences for offline access.
  Future<void> _saveBookmarksLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _bookmarkDates.map(
      (key, value) => MapEntry(key, value.toIso8601String()),
    );
    await prefs.setString('wellness_library_bookmarks', jsonEncode(data));
  }

  /// Toggles bookmark state for an item.
  ///
  /// On tap: writes to Firestore. On failure, shows error toast and does NOT
  /// mark item as bookmarked (Requirement 7.9).
  Future<void> _toggleBookmark(WellnessLibraryItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isCurrentlyBookmarked = _bookmarkedItemIds.contains(item.id);

    if (isCurrentlyBookmarked) {
      // Remove bookmark
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('wellness_library_bookmarks')
            .doc(item.id)
            .delete();

        setState(() {
          _bookmarkedItemIds.remove(item.id);
          _bookmarkDates.remove(item.id);
        });
        await _saveBookmarksLocally();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to remove bookmark. Please try again.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      // Add bookmark — write to Firestore first, only mark on success
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('wellness_library_bookmarks')
            .doc(item.id)
            .set({
          'itemId': item.id,
          'title': item.title,
          'category': item.category,
          'format': item.format,
          'bookmarkedAt': FieldValue.serverTimestamp(),
        });

        final now = DateTime.now();
        setState(() {
          _bookmarkedItemIds.add(item.id);
          _bookmarkDates[item.id] = now;
        });
        await _saveBookmarksLocally();
      } catch (e) {
        // Requirement 7.9: show error toast and don't mark as bookmarked
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to save bookmark. Please try again.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Returns recommended items (≤5) based on user's active intentions and
  /// last 7-day check-in categories (Requirement 7.7).
  List<WellnessLibraryItem> _getRecommendedItems(BuildContext context) {
    final appState = context.read<AppState>();
    final checkInState = context.read<CheckInState>();

    // Collect relevant WellnessCategories from active intentions
    final intentionCategories = <WellnessCategory>{};
    for (final intention in appState.intentions) {
      if (intention.isActive) {
        intentionCategories.add(intention.category);
      }
    }

    // Collect relevant library categories from last 7-day check-ins
    final relevantLibraryCategories = <String>{};

    // Map intention categories to library categories
    for (final entry in _categoryToWellnessCategories.entries) {
      for (final wc in entry.value) {
        if (intentionCategories.contains(wc)) {
          relevantLibraryCategories.add(entry.key);
        }
      }
    }

    // Map recent check-in mood/recovery to library categories
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final recentCheckIns = checkInState.recentCheckIns
        .where((c) => c.date.isAfter(sevenDaysAgo))
        .toList();

    for (final checkIn in recentCheckIns) {
      if (checkIn.moodState != null) {
        final mapped = _moodToCategoryMap[checkIn.moodState];
        if (mapped != null) {
          relevantLibraryCategories.addAll(mapped);
        }
      }
    }

    // If no relevant categories found, show a mix from all
    if (relevantLibraryCategories.isEmpty) {
      relevantLibraryCategories.addAll(_categories);
    }

    // Gather all items from relevant categories
    final allItems = <WellnessLibraryItem>[];
    for (final cat in relevantLibraryCategories) {
      final items = _itemsByCategory[cat];
      if (items != null) {
        allItems.addAll(items);
      }
    }

    // Remove duplicates by id and cap at 5
    final seen = <String>{};
    final recommended = <WellnessLibraryItem>[];
    for (final item in allItems) {
      if (!seen.contains(item.id) && recommended.length < 5) {
        seen.add(item.id);
        recommended.add(item);
      }
    }

    return recommended;
  }

  /// Shows an inline upgrade prompt for locked items without navigating away
  /// (Requirement 7.8).
  void _showUpgradePrompt(BuildContext context) {
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
                color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 48,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unlock Full Wellness Library',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Upgrade to Premium to access all content, including in-depth guides, audio sessions, and guided reflections across all categories.',
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

  /// Handles item card tap — opens content or shows upgrade prompt.
  ///
  /// Navigates to the appropriate content screen based on `item.format`:
  /// - `short_read` → [ShortReadScreen]
  /// - `audio` → [AudioSessionScreen]
  /// - `guided_reflection` → [GuidedReflectionScreen]
  void _onItemTap(WellnessLibraryItem item) {
    final appState = context.read<AppState>();
    final isPro = appState.isPro;

    if (!item.isFree && !isPro) {
      _showUpgradePrompt(context);
      return;
    }

    Widget screen;
    switch (item.format) {
      case 'audio':
        screen = AudioSessionScreen(item: item);
        break;
      case 'guided_reflection':
        screen = GuidedReflectionScreen(item: item);
        break;
      default:
        screen = ShortReadScreen(item: item);
        break;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(context),
          SliverPersistentHeader(
            pinned: true,
            delegate: _LibraryTabBarDelegate(
              tabBar: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor:
                    isDark ? Colors.grey[400] : Colors.grey[600],
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
                tabAlignment: TabAlignment.start,
                tabs: [
                  ..._categories.map((cat) => Tab(
                    icon: Icon(_categoryIcons[cat], size: 16),
                    text: cat,
                  )),
                  const Tab(
                    icon: Icon(Icons.bookmark_rounded, size: 16),
                    text: 'Saved',
                  ),
                ],
              ),
              backgroundColor:
                  isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            ..._categories.map((category) {
              return _buildCategoryTab(context, category);
            }),
            _buildSavedTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 110.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'WELLNESS LIBRARY',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Short reads, audio & guided reflections',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a category tab with an optional Recommended section at the top.
  Widget _buildCategoryTab(BuildContext context, String category) {
    final items = _itemsByCategory[category] ?? [];
    final recommended = _getRecommendedItems(context);
    // Filter recommended items that belong to this category
    final categoryRecommended =
        recommended.where((item) => item.category == category).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Recommended section at top (Requirement 7.7)
        if (categoryRecommended.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Recommended for You',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          ...categoryRecommended.map(
              (item) => _buildItemCard(context, item, isRecommended: true)),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.withOpacity(0.2)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'All $category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
        ...items.map((item) => _buildItemCard(context, item)),
      ],
    );
  }

  /// Builds the "Saved" tab showing bookmarked items in reverse bookmark-date
  /// order, or "No saved items yet" (Requirement 7.10).
  Widget _buildSavedTab(BuildContext context) {
    if (_isLoadingBookmarks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bookmarkedItemIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No saved items yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the bookmark icon on any item to save it here.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    // Get all bookmarked items sorted by bookmark date (reverse chronological)
    final allItems = _itemsByCategory.values.expand((items) => items).toList();
    final bookmarkedItems = allItems
        .where((item) => _bookmarkedItemIds.contains(item.id))
        .toList();

    // Sort by bookmark date descending
    bookmarkedItems.sort((a, b) {
      final dateA = _bookmarkDates[a.id] ?? DateTime(2000);
      final dateB = _bookmarkDates[b.id] ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: bookmarkedItems.length,
      itemBuilder: (context, index) {
        return _buildItemCard(context, bookmarkedItems[index]);
      },
    );
  }

  /// Builds a single content item card using FrostedContainer styling.
  Widget _buildItemCard(
    BuildContext context,
    WellnessLibraryItem item, {
    bool isRecommended = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.read<AppState>();
    final isLocked = !item.isFree && !appState.isPro;
    final isBookmarked = _bookmarkedItemIds.contains(item.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _onItemTap(item),
        child: FrostedContainer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Format icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isLocked
                            ? Colors.grey
                            : Theme.of(context).colorScheme.primary)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_rounded : item.formatIcon,
                    size: 24,
                    color: isLocked
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),

                // Title, description, and metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isLocked
                              ? (isDark ? Colors.grey[500] : Colors.grey[400])
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // Format badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.formatLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Duration badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.durationMinutes} min',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isRecommended && !isLocked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '⭐ For You',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          if (isLocked)
                            Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[400],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bookmark icon (Requirement 7.9)
                if (!isLocked)
                  IconButton(
                    onPressed: () => _toggleBookmark(item),
                    icon: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: isBookmarked
                          ? Theme.of(context).colorScheme.primary
                          : (isDark ? Colors.grey[400] : Colors.grey[500]),
                      size: 24,
                    ),
                    tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the curated content catalog.
  ///
  /// Free tier: ≥2 items per category unlocked (Requirement 7.8).
  Map<String, List<WellnessLibraryItem>> _buildLibraryItems() {
    return {
      'Recovery Education': [
        const WellnessLibraryItem(
          id: 'recov_ed_1',
          title: 'Understanding Active Recovery',
          category: 'Recovery Education',
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'Learn why gentle movement after intense days helps your body reset faster.',
          relatedCategories: [WellnessCategory.recovery],
        ),
        const WellnessLibraryItem(
          id: 'recov_ed_2',
          title: 'The Science of Rest Days',
          category: 'Recovery Education',
          format: 'short_read',
          durationMinutes: 3,
          isFree: true,
          description:
              'Why rest is productive and how to embrace recovery without guilt.',
          relatedCategories: [WellnessCategory.recovery, WellnessCategory.energy],
        ),
        const WellnessLibraryItem(
          id: 'recov_ed_3',
          title: 'Guided Recovery Body Scan',
          category: 'Recovery Education',
          format: 'audio',
          durationMinutes: 8,
          isFree: false,
          description:
              'A soothing audio body scan focused on releasing tension and aiding physical recovery.',
          relatedCategories: [WellnessCategory.recovery],
        ),
        const WellnessLibraryItem(
          id: 'recov_ed_4',
          title: 'Recovery Reflection: Listening to Your Body',
          category: 'Recovery Education',
          format: 'guided_reflection',
          durationMinutes: 6,
          isFree: false,
          description:
              'Guided prompts to help you tune into what your body needs today.',
          relatedCategories: [WellnessCategory.recovery],
        ),
      ],
      'Stress Management': [
        const WellnessLibraryItem(
          id: 'stress_1',
          title: 'Micro-Breaks for Busy Days',
          category: 'Stress Management',
          format: 'short_read',
          durationMinutes: 3,
          isFree: true,
          description:
              'Simple 1-minute resets you can do between meetings or tasks.',
          relatedCategories: [WellnessCategory.stress],
        ),
        const WellnessLibraryItem(
          id: 'stress_2',
          title: 'Evening Unwind Routine',
          category: 'Stress Management',
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'A gentle evening ritual to release the day and prepare for restful sleep.',
          relatedCategories: [WellnessCategory.stress, WellnessCategory.sleep],
        ),
        const WellnessLibraryItem(
          id: 'stress_3',
          title: 'Calm Breathing Audio Guide',
          category: 'Stress Management',
          format: 'audio',
          durationMinutes: 7,
          isFree: false,
          description:
              'A guided breathing session to help you feel calm and centred.',
          relatedCategories: [WellnessCategory.stress, WellnessCategory.mindfulness],
        ),
        const WellnessLibraryItem(
          id: 'stress_4',
          title: 'Stress Check-In Reflection',
          category: 'Stress Management',
          format: 'guided_reflection',
          durationMinutes: 5,
          isFree: false,
          description:
              'Reflective prompts to identify your stress triggers and patterns.',
          relatedCategories: [WellnessCategory.stress],
        ),
      ],
      'Sleep Improvement': [
        const WellnessLibraryItem(
          id: 'sleep_1',
          title: 'Building a Sleep Sanctuary',
          category: 'Sleep Improvement',
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'Small environment changes that make a big difference in sleep quality.',
          relatedCategories: [WellnessCategory.sleep],
        ),
        const WellnessLibraryItem(
          id: 'sleep_2',
          title: 'Wind-Down Rituals That Work',
          category: 'Sleep Improvement',
          format: 'short_read',
          durationMinutes: 3,
          isFree: true,
          description:
              'Evidence-based evening habits that signal your body it is time to rest.',
          relatedCategories: [WellnessCategory.sleep],
        ),
        const WellnessLibraryItem(
          id: 'sleep_3',
          title: 'Sleep Story: Ocean Calm',
          category: 'Sleep Improvement',
          format: 'audio',
          durationMinutes: 12,
          isFree: false,
          description:
              'A soothing narrated story designed to gently guide you into sleep.',
          relatedCategories: [WellnessCategory.sleep],
        ),
        const WellnessLibraryItem(
          id: 'sleep_4',
          title: 'Sleep Pattern Reflection',
          category: 'Sleep Improvement',
          format: 'guided_reflection',
          durationMinutes: 5,
          isFree: false,
          description:
              'Explore your sleep habits with guided prompts to find what helps you rest.',
          relatedCategories: [WellnessCategory.sleep],
        ),
      ],
      'Pilates Guidance': [
        const WellnessLibraryItem(
          id: 'pilates_1',
          title: 'Pilates for Beginners',
          category: 'Pilates Guidance',
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'The core principles of Pilates and how to start with zero experience.',
          relatedCategories: [WellnessCategory.flexibility, WellnessCategory.movement],
        ),
        const WellnessLibraryItem(
          id: 'pilates_2',
          title: 'Desk-Friendly Pilates Stretches',
          category: 'Pilates Guidance',
          format: 'short_read',
          durationMinutes: 3,
          isFree: true,
          description:
              'Quick stretches inspired by Pilates that you can do seated at your desk.',
          relatedCategories: [WellnessCategory.flexibility],
        ),
        const WellnessLibraryItem(
          id: 'pilates_3',
          title: 'Guided Mat Pilates Intro',
          category: 'Pilates Guidance',
          format: 'audio',
          durationMinutes: 10,
          isFree: false,
          description:
              'An audio-guided introductory mat Pilates session focusing on core awareness.',
          relatedCategories: [WellnessCategory.flexibility, WellnessCategory.movement],
        ),
        const WellnessLibraryItem(
          id: 'pilates_4',
          title: 'Movement Intention Reflection',
          category: 'Pilates Guidance',
          format: 'guided_reflection',
          durationMinutes: 5,
          isFree: false,
          description:
              'Set mindful movement intentions through guided journaling prompts.',
          relatedCategories: [WellnessCategory.movement],
        ),
      ],
      "Women's Wellness": [
        const WellnessLibraryItem(
          id: 'womens_1',
          title: 'Energy Management for Busy Women',
          category: "Women's Wellness",
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'Practical strategies for managing energy through demanding schedules.',
          relatedCategories: [WellnessCategory.energy, WellnessCategory.general],
        ),
        const WellnessLibraryItem(
          id: 'womens_2',
          title: 'Setting Boundaries with Grace',
          category: "Women's Wellness",
          format: 'short_read',
          durationMinutes: 4,
          isFree: true,
          description:
              'How to protect your time and energy without guilt or conflict.',
          relatedCategories: [WellnessCategory.mentalClarity, WellnessCategory.general],
        ),
        const WellnessLibraryItem(
          id: 'womens_3',
          title: 'Self-Compassion Audio Session',
          category: "Women's Wellness",
          format: 'audio',
          durationMinutes: 9,
          isFree: false,
          description:
              'A guided session to cultivate kindness toward yourself during challenging times.',
          relatedCategories: [WellnessCategory.mindfulness, WellnessCategory.general],
        ),
        const WellnessLibraryItem(
          id: 'womens_4',
          title: 'Values & Priorities Reflection',
          category: "Women's Wellness",
          format: 'guided_reflection',
          durationMinutes: 6,
          isFree: false,
          description:
              'Guided prompts to reconnect with what matters most in your life right now.',
          relatedCategories: [WellnessCategory.mentalClarity],
        ),
      ],
    };
  }
}

/// Persistent header delegate for the library tab bar.
class _LibraryTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _LibraryTabBarDelegate({required this.tabBar, required this.backgroundColor});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_LibraryTabBarDelegate oldDelegate) => false;
}
