import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class InteractivePassportCard extends StatefulWidget {
  final String displayName;
  final int countriesCount;
  final int memoriesCount;
  final GlobalKey passportKey;
  final Color? cardColor;

  const InteractivePassportCard({
    super.key,
    required this.displayName,
    required this.countriesCount,
    required this.memoriesCount,
    required this.passportKey,
    this.cardColor,
  });

  @override
  State<InteractivePassportCard> createState() => _InteractivePassportCardState();
}

class _InteractivePassportCardState extends State<InteractivePassportCard> {
  double _rotateX = 0;
  double _rotateY = 0;
  
  void _updateRotation(Offset localPosition, ui.Size size) {
    setState(() {
      _rotateX = (localPosition.dy / size.height - 0.5) * 0.4;
      _rotateY = (localPosition.dx / size.width - 0.5) * -0.4;
    });
  }

  void _resetRotation() {
    setState(() {
      _rotateX = 0;
      _rotateY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) => _updateRotation(event.localPosition, ui.Size(constraints.maxWidth, constraints.maxHeight)),
          onExit: (_) => _resetRotation(),
          child: GestureDetector(
            onPanUpdate: (event) => _updateRotation(event.localPosition, ui.Size(constraints.maxWidth, constraints.maxHeight)),
            onPanEnd: (_) => _resetRotation(),
            child: TweenAnimationBuilder<Matrix4>(
              duration: const Duration(milliseconds: 200),
              tween: Matrix4Tween(
                begin: Matrix4.identity(),
                end: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // Perspective
                  ..rotateX(_rotateX)
                  ..rotateY(_rotateY),
              ),
              builder: (context, matrix, child) {
                return Transform(
                  transform: matrix,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: AspectRatio(
                aspectRatio: 1.58,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: widget.cardColor ?? Theme.of(context).colorScheme.primary,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -20, bottom: -20,
                          child: RotationTransition(
                            turns: const AlwaysStoppedAnimation(15 / 360),
                            child: Icon(
                              Icons.explore_rounded,
                              size: 140,
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'PASSPORT',
                                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                                  ),
                                  Text(
                                    'AI WELLNESS PAL',
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.displayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'GLOBAL TRAVELER',
                                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  _buildStat('COUNTRIES', '${widget.countriesCount}'),
                                  const SizedBox(width: 48),
                                  _buildStat('MEMORIES', '${widget.memoriesCount}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Interactive shine reflection
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: LinearGradient(
                                  begin: Alignment(-1.5 + _rotateY * 2, 1.5 + _rotateX * 2),
                                  end: Alignment(1.5 + _rotateY * 2, -1.5 + _rotateX * 2),
                                  colors: [
                                    Colors.white.withOpacity(0.0),
                                    Colors.white.withOpacity(0.15),
                                    Colors.white.withOpacity(0.0),
                                  ],
                                  stops: const [0.35, 0.5, 0.65],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
