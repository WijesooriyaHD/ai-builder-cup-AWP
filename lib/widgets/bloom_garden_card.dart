import 'package:flutter/material.dart';
import 'dart:math';
import '../providers/app_state.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../screens/activity_stats_screen.dart';

class BloomGardenCard extends StatefulWidget {
  final AppState appState;
  
  const BloomGardenCard({super.key, required this.appState});

  @override
  State<BloomGardenCard> createState() => _BloomGardenCardState();
}

class _BloomGardenCardState extends State<BloomGardenCard> with TickerProviderStateMixin {
  bool _isMinimized = true;
  int? _caterpillarIndex;
  late AnimationController _fireflyController;
  final List<Firefly> _fireflies = [];
  
  // Use app theme for night mode logic
  bool get _isNight {
    return Theme.of(context).brightness == Brightness.dark;
  }
  
  @override
  void initState() {
    super.initState();
    // Schedule caterpillar spawn after first frame to safely access Theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _spawnCaterpillar();
    });
    
    // Initialize fireflies
    _fireflyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    
    for (int i = 0; i < 10; i++) {
      _fireflies.add(Firefly());
    }
  }

  @override
  void dispose() {
    _fireflyController.dispose();
    super.dispose();
  }

  void _spawnCaterpillar() {
    // Don't spawn pests if minimized, at night, or if current real streak is >= 7
    if (_isNight || widget.appState.currentStreak >= 7 || _isMinimized) {
      if (_caterpillarIndex != null) {
        setState(() => _caterpillarIndex = null);
      }
      return;
    }

    // Occasional spawn (30% chance)
    if (Random().nextDouble() < 0.3) {
      setState(() {
        _caterpillarIndex = Random().nextInt(widget.appState.gardenCells.length);
      });
    } else {
      // If we didn't spawn, clear current one to keep it occasional
      if (_caterpillarIndex != null) {
        setState(() => _caterpillarIndex = null);
      }
    }
  }

  void _toggleMinimized() {
    setState(() {
      _isMinimized = !_isMinimized;
      if (_isMinimized) {
        _caterpillarIndex = null;
      } else {
        _spawnCaterpillar();
      }
    });
  }

  void _onPesticideDropped(int index) {
    if (index == _caterpillarIndex) {
      setState(() {
        _caterpillarIndex = null;
      });
      
      // Simple success feedback
      WellnessPalSnackBar.show(
        context,
        message: "Pest cleared! Garden is safe. 🌿",
        icon: Icons.check_circle_rounded,
        iconColor: Colors.green,
      );
      
      // Spawn a new one after a delay if still expanded
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isMinimized && _caterpillarIndex == null) {
          _spawnCaterpillar();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int effectiveStreak = widget.appState.currentStreak;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ActivityStatsScreen()),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(_isMinimized ? 16 : 24),
        decoration: BoxDecoration(
          color: _isNight ? Theme.of(context).cardColor : Colors.white, // Matches app card theme at night
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: _isNight ? Colors.white10 : Colors.grey.shade100),
        ),
        child: Stack(
          children: [
            // Main Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Text(
                                  "Garden",
                                  style: TextStyle(
                                    fontSize: 22, 
                                    fontWeight: FontWeight.w900,
                                    color: _isNight ? Colors.white : Colors.black,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: _toggleMinimized,
                                  icon: Icon(
                                    _isMinimized ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                                    size: 24,
                                    color: _isNight ? Colors.white38 : Colors.grey.shade400,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isMinimized && !_isNight && effectiveStreak < 7) ...[
 // Hide pesticide after day 7
                          Draggable<bool>(
                            data: true,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Icon(
                                Icons.cleaning_services_rounded,
                                size: 40,
                                color: const Color(0xFFFF6B9D).withOpacity(0.8),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _buildHeaderIcon(Icons.cleaning_services_rounded, Colors.pink.shade50, const Color(0xFFFF6B9D)),
                            ),
                            child: _buildHeaderIcon(Icons.cleaning_services_rounded, Colors.pink.shade50, const Color(0xFFFF6B9D)),
                          ),
                          const SizedBox(width: 8),
                          const SizedBox(width: 8),
                        ],
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildHeaderIcon(
                              Icons.local_fire_department_rounded, 
                              _isNight ? Colors.white12 : Colors.green.shade50, 
                              Colors.green,
                              label: "${widget.appState.currentStreak}d",
                              textColor: _isNight ? Colors.white : null,
                            ),
                            if (widget.appState.lastMissedDays > 1)
                              Positioned(
                                top: -8,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    "-1",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth;
                    const int expCount = 5;
                    const double expSpacing = 8;
                    final double expCellSize = (width - (expSpacing * (expCount - 1))) / expCount;
                    final double expHeight = (expCellSize * expCount) + (expSpacing * (expCount - 1));

                    const int minCountRow1 = 13;
                    const double minSpacing = 4;
                    final double minCellSize = (width - (minSpacing * (minCountRow1 - 1))) / minCountRow1;
                    final double minHeight = (minCellSize * 2) + minSpacing;


                    


                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      height: _isMinimized ? minHeight : expHeight,
                      child: Stack(
                        children: List.generate(widget.appState.gardenCells.length, (index) {
                          final int expRow = index ~/ 5;
                          final int expCol = index % 5;
                          final double expLeft = expCol * (expCellSize + expSpacing);
                          final double expTop = expRow * (expCellSize + expSpacing);

                          final int minRow = index < 13 ? 0 : 1;
                          final int minCol = index < 13 ? index : index - 13;
                          final double minLeft = minCol * (minCellSize + minSpacing);
                          final double minTop = minRow * (minCellSize + minSpacing);

                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            left: _isMinimized ? minLeft : expLeft,
                            top: _isMinimized ? minTop : expTop,
                            width: _isMinimized ? minCellSize : expCellSize,
                            height: _isMinimized ? minCellSize : expCellSize,
                            child: DragTarget<bool>(
                              onAcceptWithDetails: (details) => _onPesticideDropped(index),
                              builder: (context, candidateData, rejectedData) {
                                return _buildGardenCell(
                                  widget.appState.gardenCells[index], 
                                  _isMinimized ? minCellSize : expCellSize, 
                                  _isMinimized,
                                  index,
                                  hasCaterpillar: index == _caterpillarIndex && !_isNight && effectiveStreak < 7,
                                );
                              },
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
                
                if (!_isMinimized) ...[
                  const SizedBox(height: 20),
                  Text(
                    _isNight 
                      ? "The garden sleeps under the moonlight. 🌙" 
                      : (_caterpillarIndex != null && effectiveStreak < 7 // Correct check for visible pest
                          ? "A pest is attacking your plants! Use the pesticide."
                          : (widget.appState.waterRate < 0.5 
                              ? "Your plants need more water. Stay active!" 
                              : "Your garden is thriving. Keep it up!")),
                    style: TextStyle(
                      fontSize: 14, 
                      color: _isNight 
                          ? Colors.white70 
                          : (_caterpillarIndex != null ? const Color(0xFFFF6B9D) : Colors.grey.shade600),
                      fontStyle: FontStyle.italic,
                      fontWeight: _caterpillarIndex != null && !_isNight ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),

            // Fireflies Top Layer (only at night)
            if (_isNight)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _fireflyController,
                    builder: (context, child) {
                      return Stack(
                        children: _fireflies.map((firefly) {
                          final x = firefly.getX(_fireflyController.value, 300.0);
                          final y = firefly.getY(_fireflyController.value, 300.0);
                          
                          return Positioned(
                            left: x,
                            top: y,
                            child: Opacity(
                              opacity: firefly.getOpacity(_fireflyController.value),
                              child: Container(
                                width: 4.0,
                                height: 4.0,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFFF99),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Color(0xFFFFFF99), blurRadius: 6.0, spreadRadius: 2.0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

  Widget _buildHeaderIcon(IconData icon, Color bgColor, Color iconColor, {String? label, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 13, 
                color: textColor ?? iconColor
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGardenCell(int state, double size, bool isMinimized, int index, {bool hasCaterpillar = false}) {
    Color cellColor;
    Color iconDisplayColor = Colors.transparent;
    IconData? icon;
    double iconSize = isMinimized ? size * 0.4 : 20;
    
    // Adjust colors for night mode slightly?
    // Actually, the overlay street light might handle some ambience, 
    // but let's make the base colors a bit cooler if night.

    final dynamicStreak = widget.appState.currentStreak;
    int effectiveStreak = dynamicStreak;
    
    // Determine state purely based on real streak for organic growth
    int cellState = 0;
    
    // Logic for organic growth journey linked to real streak:
    // Cells have different "thirst" levels based on index hash
    double cellThirst = ((index * 31 + 11) % 100) / 100.0; // 0.0 to 1.0
    
    // Streak required to reach state 4 (Bloom) depends on thirst
    // Some cells reach max bloom at day 4, others at day 14
    double growthProgress = (effectiveStreak / 14.0).clamp(0.0, 1.0);
    
    if (growthProgress < cellThirst * 0.2) {
      cellState = 0; // Sand
    } else if (growthProgress < cellThirst * 0.4) {
      cellState = 1; // Seed
    } else if (growthProgress < cellThirst * 0.6) {
      cellState = 2; // Sprout
    } else if (growthProgress < cellThirst * 0.8) {
      cellState = 3; // Plant
    } else {
      cellState = 4; // Bloom
    }

    final isLush = effectiveStreak >= 7;
    
    // Determine if this specific cell should show a flower (if state is 4)
    bool cellShowsFlower = false;
    bool cellShowsGrass = false;
    
    if (isLush) {
      // Deterministic hash for this cell
      double indexHash = ((index * 23 + 7) % 100) / 100.0;
      
      if (cellState == 4) {
        if (effectiveStreak >= 14) {
          cellShowsFlower = true;
        } else if (effectiveStreak >= 8) {
          double bloomProb = (effectiveStreak - 7) / 7.0;
          if (indexHash < bloomProb) {
            cellShowsFlower = true;
          }
        }
      }
      
      // If not showing a flower, show grass in lush state (day 7+)
      if (!cellShowsFlower) {
        if (indexHash < 0.8) {
          cellShowsGrass = true;
        }
      }
    }

    // Define base field colors (mix of light sand and very light green)
    final bool isSandVariant = (index * 13 + 7) % 2 == 0;
    final Color baseEmptyColor = _isNight
        ? (isSandVariant ? const Color(0xFF2D2A22) : const Color(0xFF1B241B))
        : (isSandVariant ? const Color(0xFFF7F1E3) : const Color(0xFFF1F8E9));

    final Color lushFoundationColor = _isNight ? const Color(0xFF0F140F) : const Color(0xFFFBFCFA);

    switch (cellState) {
      case 0: // Sand
        cellColor = baseEmptyColor; 
        icon = null;
        break;
      case 1: // Seed
        cellColor = isLush ? lushFoundationColor : baseEmptyColor;
        icon = Icons.fiber_manual_record;
        iconDisplayColor = _isNight ? Colors.green.shade900 : Colors.green.shade300;
        iconSize = isMinimized ? size * 0.2 : 8;
        break;
      case 2: // Sprout
        cellColor = isLush ? lushFoundationColor : baseEmptyColor;
        icon = Icons.eco_rounded;
        iconDisplayColor = _isNight ? Colors.green.shade800 : Colors.green.shade400;
        iconSize = isMinimized ? size * 0.5 : 16;
        break;
      case 3: // Plant
        cellColor = isLush ? lushFoundationColor : baseEmptyColor;
        icon = Icons.local_florist_rounded;
        iconDisplayColor = _isNight ? Colors.green.shade700 : Colors.green.shade500;
        iconSize = isMinimized ? size * 0.6 : 20;
        break;
      case 4: // Bloom
        cellColor = isLush ? lushFoundationColor : baseEmptyColor;
        icon = cellShowsFlower ? Icons.filter_vintage_rounded : Icons.auto_awesome_rounded;
        iconDisplayColor = cellShowsFlower 
            ? (_isNight ? Colors.pink.shade900 : Colors.pinkAccent) 
            : (_isNight ? Colors.green.shade600 : Colors.green.shade700);
        iconSize = cellShowsFlower 
            ? (isMinimized ? size * 0.8 : 26) 
            : (isMinimized ? size * 0.6 : 20);
        break;
      default:
        cellColor = baseEmptyColor;
        icon = null;
    }

    // Dynamic Flower and Grass styles
    if (cellShowsFlower) {
      final flowerColors = [
        const Color(0xFFFF4081), const Color(0xFFFFAB40), const Color(0xFF40C4FF),
        const Color(0xFFE040FB), const Color(0xFFFFD740), const Color(0xFF7C4DFF),
        const Color(0xFFFF5252), const Color(0xFF00E676), const Color(0xFF64FFDA),
        const Color(0xFFFF5722), const Color(0xFF00BCD4), const Color(0xFFFFEB3B),
        const Color(0xFFD81B60), const Color(0xFF6200EA), const Color(0xFFFF1493),
        const Color(0xFFDA70D6), const Color(0xFFFF7F50), const Color(0xFF00B0FF),
        const Color(0xFFFFC107), const Color(0xFFF48FB1),
      ];
      iconDisplayColor = _isNight 
          ? Color.alphaBlend(Colors.black.withOpacity(0.4), flowerColors[(index * 7 + 13) % flowerColors.length])
          : flowerColors[(index * 7 + 13) % flowerColors.length];
      cellColor = lushFoundationColor; // Lush foundation for flowers
    } else if (cellShowsGrass && cellState > 0) {
      // Grass only appears on non-sand, or as foundation
      cellColor = lushFoundationColor;
    }

    if (_isNight) {
      // Desaturate/dim colors slightly for night effect
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hasCaterpillar 
          ? Colors.red.shade50 
          : (isLush || effectiveStreak >= 1 ? cellColor : cellColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(isMinimized ? 4 : 10),
        border: Border.all(
          color: hasCaterpillar 
            ? Colors.red.shade200 
            : (_isNight ? cellColor.withOpacity(0.3) : cellColor.withOpacity(0.5)),
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (cellShowsGrass && !cellShowsFlower)
            Opacity(
              opacity: 0.3,
              child: Icon(
                Icons.grass_rounded,
                color: Colors.green.shade400,
                size: isMinimized ? size * 0.7 : 24,
              ),
            ),
          if (isLush) ...[
            Positioned(top: 0, left: 0, child: Icon(Icons.auto_awesome_rounded, size: isMinimized ? 8 : 14, color: (_isNight ? Colors.green.shade900 : Colors.green.shade200).withOpacity(0.5))),
            Positioned(top: 0, right: 0, child: Icon(Icons.auto_awesome_rounded, size: isMinimized ? 8 : 14, color: (_isNight ? Colors.green.shade900 : Colors.green.shade200).withOpacity(0.5))),
            Positioned(bottom: 0, left: 0, child: Icon(Icons.auto_awesome_rounded, size: isMinimized ? 8 : 14, color: (_isNight ? Colors.green.shade900 : Colors.green.shade200).withOpacity(0.5))),
            Positioned(bottom: 0, right: 0, child: Icon(Icons.auto_awesome_rounded, size: isMinimized ? 8 : 14, color: (_isNight ? Colors.green.shade900 : Colors.green.shade200).withOpacity(0.5))),
          ],
          if (icon != null) 
            Icon(
              icon, 
              color: iconDisplayColor, 
              size: iconSize > 0 ? iconSize : 1.0,
            ),
          if (hasCaterpillar)
            const Text("🐛", style: TextStyle(fontSize: 20)),
          
          if (_isNight)
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(isMinimized ? 4 : 10),
              ),
            ),
        ],
      ),
    );
  }
}

class Firefly {
  final Random _random = Random();
  late double _startX;
  late double _startY;
  late double _speedX;
  late double _speedY;
  late double _phase;

  Firefly() {
    _reset();
  }

  void _reset() {
    _startX = _random.nextDouble();
    _startY = _random.nextDouble();
    _speedX = (_random.nextDouble() - 0.5) * 0.2;
    _speedY = (_random.nextDouble() - 0.5) * 0.2;
    _phase = _random.nextDouble() * 2 * pi;
  }

  double getX(double time, double width) {
    return (_startX + sin(time * 2 * pi + _phase) * 0.1 + time * _speedX * 5) % 1.0 * width;
  }

  double getY(double time, double height) {
    return (_startY + cos(time * 2 * pi + _phase) * 0.1 + time * _speedY * 5) % 1.0 * height;
  }
  
  double getOpacity(double time) {
    return 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 5 + _phase)); // Blink effect
  }
}
