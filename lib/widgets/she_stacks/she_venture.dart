import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SheVentureGame extends StatefulWidget {
  final Function(int) onComplete;
  const SheVentureGame({super.key, required this.onComplete});

  @override
  State<SheVentureGame> createState() => _SheVentureGameState();
}

class _SheVentureGameState extends State<SheVentureGame> {
  static const int gridSize = 4;
  List<List<int>> grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
  int score = 0;
  bool isGameOver = false;
  bool isWon = false;
  
  // Tips & Milestones
  final Set<int> _reachedStages = {};
  String? _currentTip;
  String? _currentBiz;
  String? _currentQuote;
  String? _currentFounder;
  bool _showTip = false;
  bool _isFactView = true;

  final Map<int, Map<String, String>> _founderTips = {
    4: {
      "tip": "Sophia Amoruso was 22 when she started Nasty Gal on eBay. She turned her passion for vintage into a multi-million dollar fashion empire.",
      "biz": "DON'T WAIT FOR PERMISSION. Start with what you have, where you are. Passion is your first investor.",
      "quote": "GIRLBOSS.",
      "founder": "Sophia Amoruso"
    },
    8: {
      "tip": "Emily Weiss launched 'Into The Gloss' at 25 while working as an assistant. She turned her blog into the billion-dollar beauty brand Glossier.",
      "quote": "Blogging to Beauty.",
      "biz": "CONTENT IS CURRENCY. Build an audience before you build a product. Trust is the hardest thing to scale.",
      "founder": "Emily Weiss"
    },
    16: {
      "tip": "Sara Blakely started Spanx at 27 with \$5,000 in savings while selling fax machines. She failed the LSAT twice but never stopped trying.",
      "quote": "Founder of Spanx.",
      "biz": "EMBRACE FAILURE. If you aren't failing, you aren't growing. Make failure your best friend, not your enemy.",
      "founder": "Sara Blakely"
    },
    32: {
      "tip": "Melanie Perkins was rejected by 100+ investors before Canva took off when she was 26. She's now one of the world's youngest tech billionaire CEOs.",
      "quote": "CEO of Canva.",
      "biz": "PERSISTENCE PAYS. A 'no' is just a 'not yet'. Keep iterating your pitch until it's impossible to ignore.",
      "founder": "Melanie Perkins"
    },
    64: {
      "tip": "Whitney Wolfe Herd founded Bumble at 25 to empower women. At 31, she became the youngest self-made female billionaire to take a company public.",
      "quote": "Bumble Founder.",
      "biz": "REWRITE THE RULES. If the industry bias blocks you, build your own table with your own rules.",
      "founder": "Whitney Wolfe Herd"
    },
    128: {
      "tip": "Falguni Nayar left a top banking career to start Nykaa at age 50. She built India's first beauty unicorn with zero retail experience.",
      "quote": "Founder of Nykaa.",
      "biz": "IT'S NEVER TOO LATE. Experience in other fields is a superpower. Use your maturity as your competitive edge.",
      "founder": "Falguni Nayar"
    },
    256: {
      "tip": "Katrina Lake founded Stitch Fix at 28. At 34, she was the youngest woman to lead an IPO, proving your data-driven vision can scale.",
      "quote": "Stitch Fix Founder.",
      "biz": "LEAN INTO DATA. Intuition gets you started; data keeps you growing. Master your metrics early.",
      "founder": "Katrina Lake"
    },
    512: {
      "tip": "Julia Hartz co-founded Eventbrite at 26. She led the company through a successful IPO, proving women can dominate the global event tech market.",
      "quote": "Eventbrite CEO.",
      "biz": "BUILD FOR SCALE. Think about your 100th employee when you're hiring your 1st. Systems allow you to soar.",
      "founder": "Julia Hartz"
    },
    1024: {
      "tip": "Oprah Winfrey became a millionaire at 32 when her show went national. At 49, she became the first Black woman billionaire in history.",
      "quote": "Ownership & Empire.",
      "biz": "OWN YOUR NARRATIVE. Control your brand, your equity, and your voice. Authenticity is the ultimate scale.",
      "founder": "Oprah Winfrey"
    },
    2048: {
      "tip": "Madam C.J. Walker was born on a plantation but became America's first self-made female millionaire, creating jobs for 40,000 people.",
      "quote": "BUILD THE LEGACY.",
      "biz": "COMMUNITY IMPACT. True ventures solve real problems for real people. Your legacy is measured by lives changed.",
      "founder": "Madam C.J. Walker"
    },
  };

  @override
  void initState() {
    super.initState();
    _addNewTile();
    _addNewTile();
  }

  void _addNewTile() {
    List<math.Point<int>> emptyCells = [];
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (grid[r][c] == 0) emptyCells.add(math.Point(r, c));
      }
    }
    if (emptyCells.isNotEmpty) {
      final point = emptyCells[math.Random().nextInt(emptyCells.length)];
      setState(() {
        grid[point.x][point.y] = (math.Random().nextDouble() < 0.9) ? 2 : 4;
      });
    }
  }

  void _handleSwipe(Offset delta) {
    if (isGameOver) return;
    
    bool moved = false;
    if (delta.dx.abs() > delta.dy.abs()) {
      if (delta.dx > 0) {
        moved = _moveRight();
      } else {
        moved = _moveLeft();
      }
    } else {
      if (delta.dy > 0) {
        moved = _moveDown();
      } else {
        moved = _moveUp();
      }
    }

    if (moved) {
      HapticFeedback.lightImpact();
      _addNewTile();
      _checkGameState();
    }
  }

  bool _moveLeft() {
    bool moved = false;
    for (int r = 0; r < gridSize; r++) {
      List<int> row = grid[r].where((e) => e != 0).toList();
      for (int i = 0; i < row.length - 1; i++) {
        if (row[i] == row[i + 1]) {
          row[i] *= 2;
          score += row[i];
          _checkNewMilestone(row[i]);
          row.removeAt(i + 1);
          moved = true;
        }
      }
      List<int> newRow = List.from(row)..addAll(List.filled(gridSize - row.length, 0));
      if (!_listEquals(grid[r], newRow)) {
        grid[r] = newRow;
        moved = true;
      }
    }
    return moved;
  }

  bool _moveRight() {
    bool moved = false;
    for (int r = 0; r < gridSize; r++) {
      List<int> row = grid[r].where((e) => e != 0).toList();
      for (int i = row.length - 1; i > 0; i--) {
        if (row[i] == row[i - 1]) {
          row[i] *= 2;
          score += row[i];
          _checkNewMilestone(row[i]);
          row.removeAt(i - 1);
          moved = true;
        }
      }
      List<int> newRow = List.filled(gridSize - row.length, 0)..addAll(row);
      if (!_listEquals(grid[r], newRow)) {
        grid[r] = newRow;
        moved = true;
      }
    }
    return moved;
  }

  bool _moveUp() {
    bool moved = false;
    for (int c = 0; c < gridSize; c++) {
      List<int> col = [];
      for (int r = 0; r < gridSize; r++) {
        if (grid[r][c] != 0) col.add(grid[r][c]);
      }
      for (int i = 0; i < col.length - 1; i++) {
        if (col[i] == col[i + 1]) {
          col[i] *= 2;
          score += col[i];
          _checkNewMilestone(col[i]);
          col.removeAt(i + 1);
          moved = true;
        }
      }
      for (int r = 0; r < gridSize; r++) {
        int val = r < col.length ? col[r] : 0;
        if (grid[r][c] != val) {
          grid[r][c] = val;
          moved = true;
        }
      }
    }
    return moved;
  }

  bool _moveDown() {
    bool moved = false;
    for (int c = 0; c < gridSize; c++) {
      List<int> col = [];
      for (int r = 0; r < gridSize; r++) {
        if (grid[r][c] != 0) col.add(grid[r][c]);
      }
      for (int i = col.length - 1; i > 0; i--) {
        if (col[i] == col[i - 1]) {
          col[i] *= 2;
          score += col[i];
          _checkNewMilestone(col[i]);
          col.removeAt(i - 1);
          moved = true;
        }
      }
      for (int r = gridSize - 1; r >= 0; r--) {
        int colIndex = col.length - 1 - (gridSize - 1 - r);
        int val = colIndex >= 0 ? col[colIndex] : 0;
        if (grid[r][c] != val) {
          grid[r][c] = val;
          moved = true;
        }
      }
    }
    return moved;
  }

  bool _listEquals(List<int> a, List<int> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _checkGameState() {
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (grid[r][c] == 2048) isWon = true;
        if (grid[r][c] == 0) return;
        if (r < gridSize - 1 && grid[r][c] == grid[r + 1][c]) return;
        if (c < gridSize - 1 && grid[r][c] == grid[r][c + 1]) return;
      }
    }
    setState(() => isGameOver = true);
  }

  void _checkNewMilestone(int value) {
    if (_founderTips.containsKey(value) && !_reachedStages.contains(value)) {
      _reachedStages.add(value);
      setState(() {
        _currentTip = _founderTips[value]!["tip"];
        _currentBiz = _founderTips[value]!["biz"];
        _currentQuote = _founderTips[value]!["quote"];
        _currentFounder = _founderTips[value]!["founder"];
        _isFactView = math.Random().nextBool(); // Randomly choose view type
        _showTip = true;
      });
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _showTip = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildTipArea(),
                    const SizedBox(height: 24),
                    _buildGrid(),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            if (isGameOver || isWon) _buildEndOverlay(),
            Positioned(
              top: 10,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SHE VENTURE", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                Text("Build your Unicorn", style: TextStyle(color: Colors.purple.shade200, fontWeight: FontWeight.bold)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  const Text("VALUATION", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("\$${score}M", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _buildActionButton(
              icon: Icons.refresh_rounded,
              label: "RESET",
              color: Colors.orangeAccent,
              onTap: _resetGame,
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              icon: Icons.help_outline_rounded,
              label: "HOW TO PLAY",
              color: Colors.blueAccent,
              onTap: _showHowToPlay,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _resetGame() {
    setState(() {
      grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
      score = 0;
      isGameOver = false;
      isWon = false;
      _reachedStages.clear();
      _showTip = false;
      _addNewTile();
      _addNewTile();
    });
    HapticFeedback.mediumImpact();
  }

  void _showHowToPlay() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            _buildInstructions(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("GOT IT!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GestureDetector(
      onPanEnd: (details) => _handleSwipe(details.velocity.pixelsPerSecond),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
          ),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridSize,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: gridSize * gridSize,
            itemBuilder: (context, index) {
              int r = index ~/ gridSize;
              int c = index % gridSize;
              return _buildTile(grid[r][c]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTile(int value) {
    if (value == 0) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    final config = _getTileConfig(value);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [config.color, config.color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: config.color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(config.icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  config.label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(duration: 200.ms, curve: Curves.easeOutBack);
  }

  _TileConfig _getTileConfig(int value) {
    switch (value) {
      case 2: return _TileConfig("Concept", Icons.lightbulb_outline_rounded, Colors.blueGrey);
      case 4: return _TileConfig("Prototype", Icons.architecture_rounded, Colors.blue);
      case 8: return _TileConfig("MVP", Icons.rocket_launch_rounded, Colors.cyan);
      case 16: return _TileConfig("Seed", Icons.grass_rounded, Colors.teal);
      case 32: return _TileConfig("Series A", Icons.trending_up_rounded, Colors.green);
      case 64: return _TileConfig("Series B", Icons.groups_rounded, Colors.green);
      case 128: return _TileConfig("Series C", Icons.domain_rounded, Colors.orange);
      case 256: return _TileConfig("Growth", Icons.speed_rounded, Colors.deepOrange);
      case 512: return _TileConfig("Leader", Icons.diamond_rounded, Colors.purple);
      case 1024: return _TileConfig("Soonicorn", Icons.stars_rounded, Colors.indigo);
      case 2048: return _TileConfig("Unicorn", Icons.auto_awesome_rounded, Colors.pinkAccent);
      default: return _TileConfig("Venture", Icons.business_center_rounded, Colors.grey);
    }
  }

  Widget _buildEndOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isWon ? Icons.emoji_events_rounded : Icons.sms_failed_rounded, 
                 size: 80, color: isWon ? Colors.amber : Colors.redAccent),
            const SizedBox(height: 24),
            Text(isWon ? "UNICORN ACHIEVED!" : "VENTURE STALLED", 
                 style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text("Final Valuation: \$${score}M", style: TextStyle(color: Colors.purple.shade200, fontSize: 18)),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                backgroundColor: Colors.purpleAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                widget.onComplete(score ~/ 10);
                Navigator.pop(context);
              },
              child: const Text("CLAIM XP", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  Widget _buildTipArea() {
    return AnimatedContainer(
      duration: 400.ms,
      curve: Curves.easeInOut,
      width: double.infinity,
      height: 200, // Increased height to prevent overflows
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _showTip ? Colors.white : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _showTip 
            ? (_isFactView ? Colors.purpleAccent : Colors.blueAccent) 
            : Colors.white.withOpacity(0.05)
        ),
        boxShadow: _showTip ? [
          BoxShadow(
            color: (_isFactView ? Colors.purpleAccent : Colors.blueAccent).withOpacity(0.3), 
            blurRadius: 15, 
            spreadRadius: 2
          ),
        ] : [],
      ),
      child: Center(
        child: _showTip ? _buildActiveTip() : _buildLockedTip(),
      ),
    );
  }

  Widget _buildActiveTip() {
    final color = _isFactView ? Colors.purple : Colors.blue;
    final accentColor = _isFactView ? Colors.purpleAccent : Colors.blueAccent;
    final title = _isFactView ? "FOUNDER FACT: $_currentQuote" : "VENTURE STRATEGY";
    final bodyText = _isFactView ? (_currentTip ?? "") : (_currentBiz ?? "");
    final footer = _isFactView ? "— $_currentFounder" : "Strategic Insight";

    return Stack(
      children: [
        Column(
          key: ValueKey("$_currentQuote$_isFactView"),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isFactView ? Icons.auto_awesome_rounded : Icons.trending_up_rounded, 
                     color: accentColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color.shade900,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              bodyText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              footer,
              style: TextStyle(
                color: color.shade700,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
        Positioned(
          top: -15,
          right: -15,
          child: IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400),
            onPressed: () => setState(() => _showTip = false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }

  Widget _buildLockedTip() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, color: Colors.white24, size: 14),
            const SizedBox(width: 8),
            const Text(
              "FOUNDER WISDOM LOCKED",
              style: TextStyle(
                color: Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Scale your venture to unlock real-life insights.",
          style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Colors.purple.shade200),
              const SizedBox(width: 8),
              const Text("HOW TO PLAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInstructionStep("Swipe to merge", "Combine two identical venture stages to advance."),
          _buildInstructionStep("Scale your startup", "Concept → Seed → MVP → Series A ... → Unicorn!"),
          _buildInstructionStep("Build Valuation", "Reach \$2048M to achieve legendary Unicorn status."),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(color: Colors.purpleAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(desc, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileConfig {
  final String label;
  final IconData icon;
  final Color color;
  _TileConfig(this.label, this.icon, this.color);
}
