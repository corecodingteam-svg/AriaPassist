import 'dart:async';
import 'dart:math' as math;

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:flutter/material.dart';

/// Brief confetti burst over the whole screen (≈1.4 s). Skipped entirely
/// when reduce-motion is on; the caller still shows/speaks the message.
void showConfetti(BuildContext context) {
  if (context.tokens.motion == Duration.zero) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        IgnorePointer(child: _Confetti(onDone: () => entry.remove())),
  );
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final _rnd = math.Random(7);
  late final List<_Bit> _bits = List.generate(
    70,
    (_) => _Bit(
      x: _rnd.nextDouble(),
      speed: 0.6 + _rnd.nextDouble() * 0.8,
      drift: (_rnd.nextDouble() - 0.5) * 0.3,
      spin: _rnd.nextDouble() * 6,
      hue: _rnd.nextInt(5),
    ),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_c.forward().whenComplete(widget.onDone));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = [
      p.primary,
      p.secondary,
      p.success,
      p.warning,
      p.gradientEnd,
    ];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(_bits, _c.value, colors),
      ),
    );
  }
}

class _Bit {
  _Bit({
    required this.x,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.hue,
  });
  final double x;
  final double speed;
  final double drift;
  final double spin;
  final int hue;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t, this.colors);
  final List<_Bit> bits;
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final b in bits) {
      final y = -20 + t * b.speed * (size.height + 40);
      final x = (b.x + b.drift * t) * size.width;
      paint.color = colors[b.hue].withValues(alpha: 1 - t * 0.6);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(b.spin * t * math.pi)
        ..drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
