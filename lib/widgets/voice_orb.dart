import 'dart:math';
import 'package:flutter/material.dart';

import '../services/voice_command_service.dart';

/// A Siri-style animated gradient orb that responds to voice input.
///
/// Shows different animation states:
/// - [VoiceAssistantState.idle]: Gentle pulse with soft gradient
/// - [VoiceAssistantState.listening]: Energetic morphing with amplitude response
/// - [VoiceAssistantState.processing]: Spinning/thinking animation
/// - [VoiceAssistantState.speaking]: Rhythmic pulse synced to TTS output
class VoiceOrb extends StatefulWidget {
  final VoiceAssistantState state;
  final double soundLevel;
  final double size;
  final Color? primaryColor;

  const VoiceOrb({
    super.key,
    required this.state,
    this.soundLevel = 0.0,
    this.size = 120,
    this.primaryColor,
  });

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _morphController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimationSpeed();
  }

  void _updateAnimationSpeed() {
    switch (widget.state) {
      case VoiceAssistantState.idle:
        _pulseController.duration = const Duration(milliseconds: 2000);
        _rotationController.duration = const Duration(milliseconds: 6000);
        break;
      case VoiceAssistantState.listening:
        _pulseController.duration = const Duration(milliseconds: 800);
        _rotationController.duration = const Duration(milliseconds: 2000);
        break;
      case VoiceAssistantState.processing:
        _pulseController.duration = const Duration(milliseconds: 1000);
        _rotationController.duration = const Duration(milliseconds: 1500);
        break;
      case VoiceAssistantState.speaking:
        _pulseController.duration = const Duration(milliseconds: 1200);
        _rotationController.duration = const Duration(milliseconds: 4000);
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _rotationController, _morphController]),
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _OrbPainter(
            state: widget.state,
            soundLevel: widget.soundLevel,
            pulseValue: _pulseController.value,
            rotationValue: _rotationController.value,
            morphValue: _morphController.value,
            primaryColor: primary,
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final VoiceAssistantState state;
  final double soundLevel;
  final double pulseValue;
  final double rotationValue;
  final double morphValue;
  final Color primaryColor;

  _OrbPainter({
    required this.state,
    required this.soundLevel,
    required this.pulseValue,
    required this.rotationValue,
    required this.morphValue,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.35;

    // Draw outer glow rings
    _drawGlowRings(canvas, center, baseRadius, size);

    // Draw the main orb
    _drawOrb(canvas, center, baseRadius, size);

    // Draw inner highlight
    _drawInnerHighlight(canvas, center, baseRadius);
  }

  void _drawGlowRings(Canvas canvas, Offset center, double baseRadius, Size size) {
    final ringCount = state == VoiceAssistantState.listening ? 4 : 2;
    final amplitudeBoost = state == VoiceAssistantState.listening ? soundLevel * 0.3 : 0.0;

    for (int i = 0; i < ringCount; i++) {
      final progress = (pulseValue + i * 0.25) % 1.0;
      final ringRadius = baseRadius + (progress * baseRadius * 0.6) + (amplitudeBoost * baseRadius);
      final opacity = (1.0 - progress) * 0.3;

      final paint = Paint()
        ..color = primaryColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - progress);

      canvas.drawCircle(center, ringRadius, paint);
    }
  }

  void _drawOrb(Canvas canvas, Offset center, double baseRadius, Size size) {
    final amplitudeScale = state == VoiceAssistantState.listening
        ? 1.0 + soundLevel * 0.15
        : 1.0 + pulseValue * 0.05;

    final radius = baseRadius * amplitudeScale;

    // Create gradient colors based on state
    final List<Color> gradientColors;
    switch (state) {
      case VoiceAssistantState.idle:
        gradientColors = [
          primaryColor.withOpacity(0.6),
          primaryColor.withOpacity(0.3),
          primaryColor.withOpacity(0.1),
        ];
        break;
      case VoiceAssistantState.listening:
        gradientColors = [
          primaryColor,
          Color.lerp(primaryColor, Colors.purpleAccent, morphValue) ?? primaryColor,
          Color.lerp(primaryColor, Colors.cyanAccent, 1.0 - morphValue) ?? primaryColor,
        ];
        break;
      case VoiceAssistantState.processing:
        gradientColors = [
          Color.lerp(primaryColor, Colors.amber, pulseValue) ?? primaryColor,
          primaryColor,
          Color.lerp(primaryColor, Colors.deepPurple, pulseValue) ?? primaryColor,
        ];
        break;
      case VoiceAssistantState.speaking:
        gradientColors = [
          primaryColor.withOpacity(0.8),
          Color.lerp(primaryColor, Colors.tealAccent, morphValue * 0.5) ?? primaryColor,
          primaryColor.withOpacity(0.5),
        ];
        break;
    }

    // Rotate the gradient
    final angle = rotationValue * 2 * pi;

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: angle,
      endAngle: angle + 2 * pi,
      colors: [...gradientColors, gradientColors.first],
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    // Apply morphing distortion when listening
    if (state == VoiceAssistantState.listening && soundLevel > 0.1) {
      final path = _createMorphedPath(center, radius, soundLevel);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawCircle(center, radius, paint);
    }

    // Add a soft blur effect via layered circles
    final blurPaint = Paint()
      ..color = primaryColor.withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(center, radius * 1.1, blurPaint);
  }

  Path _createMorphedPath(Offset center, double radius, double amplitude) {
    final path = Path();
    final points = 60;
    final distortion = amplitude * radius * 0.12;

    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * 2 * pi;
      final noise = sin(angle * 3 + rotationValue * 2 * pi) * distortion +
          cos(angle * 5 + morphValue * pi) * distortion * 0.5;
      final r = radius + noise;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  void _drawInnerHighlight(Canvas canvas, Offset center, double baseRadius) {
    final highlightOffset = Offset(
      center.dx - baseRadius * 0.2,
      center.dy - baseRadius * 0.2,
    );

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.3 * pulseValue),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: highlightOffset, radius: baseRadius * 0.4));

    canvas.drawCircle(highlightOffset, baseRadius * 0.4, highlightPaint);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => true;
}
