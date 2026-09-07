import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class SnowOverlay extends StatefulWidget {
  final Widget child;

  const SnowOverlay({super.key, required this.child});

  @override
  State<SnowOverlay> createState() => _SnowOverlayState();
}

class _SnowOverlayState extends State<SnowOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Snowflake> _snowflakes = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // Initial snowflakes
    for (int i = 0; i < 50; i++) {
      _snowflakes.add(Snowflake(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: _random.nextDouble() * 2 + 1,
        speed: (_random.nextDouble() * 0.05 + 0.02) * 0.15, // Even slower
        drift: _random.nextDouble() * 0.02 - 0.01,
        color: _random.nextBool() 
            ? Colors.white.withOpacity(0.6) 
            : Colors.lightBlue.withOpacity(0.4),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWinterMode = context.select<AppState, bool>((s) => s.isWinterMode);

    if (!isWinterMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              _updateSnowflakes();
              return CustomPaint(
                painter: SnowPainter(_snowflakes),
                size: Size.infinite,
              );
            },
          ),
        ),
      ],
    );
  }

  void _updateSnowflakes() {
    for (var flake in _snowflakes) {
      flake.y += flake.speed * 0.1;
      flake.x += flake.drift * 0.1;

      if (flake.y > 1.1) {
        flake.y = -0.1;
        flake.x = _random.nextDouble();
      }
      if (flake.x > 1.1) flake.x = -0.1;
      if (flake.x < -0.1) flake.x = 1.1;
    }
  }
}

class Snowflake {
  double x;
  double y;
  double radius;
  double speed;
  double drift;
  Color color;

  Snowflake({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.drift,
    required this.color,
  });
}

class SnowPainter extends CustomPainter {
  final List<Snowflake> snowflakes;

  SnowPainter(this.snowflakes);

  @override
  void paint(Canvas canvas, Size size) {
    for (var flake in snowflakes) {
      final paint = Paint()
        ..color = flake.color
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(
        Offset(flake.x * size.width, flake.y * size.height),
        flake.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SnowPainter oldDelegate) => true;
}
