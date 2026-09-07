import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A lightweight, dependency-free "AI + wellness" loading animation.
///
/// Draws a soft breathing glow, a slowly rotating dashed "neural" ring,
/// a counter-rotating inner arc, and orbiting particles around a central
/// AI spark — evoking both intelligence and calm/wellness.
///
/// Tinted with [color]. Used while the AI generates plans and intention tasks.
class AiWellnessLoader extends StatefulWidget {
  /// Accent color for the animation.
  final Color color;

  /// Overall size (width & height) of the loader.
  final double size;

  const AiWellnessLoader({
    super.key,
    required this.color,
    this.size = 180,
  });

  @override
  State<AiWellnessLoader> createState() => _AiWellnessLoaderState();
}

class _AiWellnessLoaderState extends State<AiWellnessLoader>
    with TickerProviderStateMixin {
  // Slow, continuous rotation for the orbiting particles + sparkle ring.
  late final AnimationController _orbitController;
  // Gentle "breathing" pulse for the AI core (wellness/calm feel).
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_orbitController, _pulseController]),
        builder: (context, _) {
          final pulse = Curves.easeInOut.transform(_pulseController.value);
          return CustomPaint(
            painter: _AiWellnessLoaderPainter(
              orbit: _orbitController.value,
              pulse: pulse,
              color: widget.color,
              isDark: Theme.of(context).brightness == Brightness.dark,
            ),
            child: Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                size: (widget.size * 0.19) + pulse * 6,
                color: widget.color,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AiWellnessLoaderPainter extends CustomPainter {
  final double orbit; // 0..1 rotation phase
  final double pulse; // 0..1 breathing phase
  final Color color;
  final bool isDark;

  _AiWellnessLoaderPainter({
    required this.orbit,
    required this.pulse,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final angle = orbit * 2 * math.pi;

    // 1. Soft breathing glow behind the core.
    final glowRadius = maxR * (0.42 + pulse * 0.10);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(0.28),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Rotating dashed "neural" ring.
    final ringRadius = maxR * 0.66;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.55);
    const dashes = 24;
    for (int i = 0; i < dashes; i++) {
      if (i.isOdd) continue;
      final a = angle + (i / dashes) * 2 * math.pi;
      final start = Offset(
        center.dx + ringRadius * math.cos(a),
        center.dy + ringRadius * math.sin(a),
      );
      final end = Offset(
        center.dx + (ringRadius + 6) * math.cos(a),
        center.dy + (ringRadius + 6) * math.sin(a),
      );
      canvas.drawLine(start, end, ringPaint);
    }

    // 3. Counter-rotating inner arc for depth.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.9);
    final arcRect = Rect.fromCircle(center: center, radius: maxR * 0.5);
    canvas.drawArc(arcRect, -angle, math.pi * 0.8, false, arcPaint);

    // 4. Orbiting particles (three, evenly spaced) — the "wellness" motes.
    for (int i = 0; i < 3; i++) {
      final pa = angle * 1.4 + i * (2 * math.pi / 3);
      final pr = maxR * (0.80 + 0.04 * math.sin(angle * 2 + i));
      final p = Offset(
        center.dx + pr * math.cos(pa),
        center.dy + pr * math.sin(pa),
      );
      canvas.drawCircle(p, 4.5, Paint()..color = color.withOpacity(0.9));
      canvas.drawCircle(p, 8, Paint()..color = color.withOpacity(0.15));
    }

    // 5. Core disc under the spark icon.
    final corePaint = Paint()..color = color.withOpacity(isDark ? 0.22 : 0.14);
    canvas.drawCircle(center, maxR * 0.30 + pulse * 3, corePaint);
  }

  @override
  bool shouldRepaint(_AiWellnessLoaderPainter old) =>
      old.orbit != orbit ||
      old.pulse != pulse ||
      old.color != color ||
      old.isDark != isDark;
}
