import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A reusable glassmorphism container that applies a frosted-glass effect
/// using [BackdropFilter] and [ClipRRect].
///
/// Wraps [child] in a blurred, semi-transparent container with a subtle border,
/// giving a modern frosted-glass (glassmorphism) appearance.
class FrostedContainer extends StatelessWidget {
  const FrostedContainer({
    super.key,
    required this.child,
    this.blur = 15,
    this.opacity = 0.15,
    this.borderRadius = AppTheme.borderRadius,
  });

  /// The widget to display inside the frosted container.
  final Widget child;

  /// The blur intensity applied to the backdrop. Defaults to 15.
  final double blur;

  /// The opacity of the white background overlay. Defaults to 0.15.
  final double opacity;

  /// The border radius of the container. Defaults to [AppTheme.borderRadius].
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // On dark backgrounds a translucent white overlay reads as frosted glass.
    // On light backgrounds white-on-white is invisible, so use an opaque-ish
    // surface fill with a darker border and a soft shadow so the tile is
    // clearly visible.
    final Color fillColor = isDark
        ? Colors.white.withOpacity(opacity)
        : Colors.white.withOpacity(0.75);

    final Color borderColor = isDark
        ? Colors.white.withOpacity(0.2)
        : Colors.black.withOpacity(0.08);

    // Shadow lives on an outer container (outside the ClipRRect) so it isn't
    // clipped away. Only shown in light theme where tiles need lift.
    final List<BoxShadow>? shadows = isDark
        ? null
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
