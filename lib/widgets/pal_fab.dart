import 'package:flutter/material.dart';

import '../services/voice_command_service.dart';
import 'voice_orb.dart';

/// The animated "summon your Pal" button that floats above the bottom nav.
///
/// Renders the very same [VoiceOrb] the Wellness Pal sheet uses, just smaller —
/// so the button and the orb the user taps inside the sheet are visibly the
/// same object, with the same sweeping gradient, expanding glow rings, blur
/// halo and inner highlight. It is driven by the live assistant state, so the
/// orb on the FAB reacts (speeds up, morphs to the mic amplitude) exactly as
/// the big one does.
///
/// Motion is the point here, so it animates while idle — but the whole thing
/// renders a static frame when the platform asks for reduced motion.
class PalFab extends StatefulWidget {
  /// Assistant state driving the orb. Idle gives the calm ambient animation;
  /// listening/processing/speaking give the energetic ones.
  final VoiceAssistantState state;

  /// Mic amplitude 0..1, used by the orb's morphing while listening.
  final double soundLevel;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Diameter of the orb itself. The widget reserves extra room around it so
  /// the orb's glow rings — which extend past its nominal size — aren't clipped.
  final double size;

  const PalFab({
    super.key,
    required this.state,
    required this.onTap,
    required this.onLongPress,
    this.soundLevel = 0.0,
    this.size = 60,
  });

  @override
  State<PalFab> createState() => _PalFabState();
}

class _PalFabState extends State<PalFab> {
  bool _pressed = false;

  bool get _isActive => widget.state != VoiceAssistantState.idle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    // The orb's glow rings reach ~0.56x its size from centre, so the box needs
    // to be a little larger than the orb or the outermost ring gets clipped.
    final extent = widget.size * 1.25;

    // Reduced Motion: render a single static frame instead of the loops.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final Widget orb = reduceMotion
        ? _StaticOrb(size: widget.size, color: primary, isActive: _isActive)
        : VoiceOrb(
            state: widget.state,
            soundLevel: widget.soundLevel,
            size: widget.size,
            primaryColor: primary,
          );

    return Semantics(
      button: true,
      label: 'Wellness Pal',
      hint: 'Double tap to talk, long press to open without starting',
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: extent,
            height: extent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A solid disc behind the orb: the orb is semi-transparent at
                // its edges, and without this the content scrolling underneath
                // shows through and makes the button hard to read.
                Container(
                  width: widget.size * 0.82,
                  height: widget.size * 0.82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF1C1A27) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.14),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                orb,
                // Affordance: without an icon the orb alone doesn't read as a
                // button. Kept small and translucent so it sits in the orb
                // rather than on top of it.
                Icon(
                  _isActive ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                  size: widget.size * 0.34,
                  color: Colors.white.withOpacity(_isActive ? 0.95 : 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-animated stand-in used when the platform asks for reduced motion.
/// Mirrors the orb's resting look — a soft radial disc — without any loops.
class _StaticOrb extends StatelessWidget {
  const _StaticOrb({
    required this.size,
    required this.color,
    required this.isActive,
  });

  final double size;
  final Color color;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.7,
      height: size * 0.7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(isActive ? 0.95 : 0.65),
            color.withOpacity(isActive ? 0.55 : 0.30),
          ],
        ),
      ),
    );
  }
}
