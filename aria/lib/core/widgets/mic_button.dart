import 'package:aria/core/theme/aria_tokens.dart';
import 'package:flutter/material.dart';

/// 64 px gradient mic button, raised above the nav bar. Pulses while
/// [listening] (unless reduce-motion is on).
class MicButton extends StatefulWidget {
  const MicButton({required this.onPressed, this.listening = false, super.key});

  final VoidCallback onPressed;
  final bool listening;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(MicButton old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    final animate = widget.listening && context.tokens.motion != Duration.zero;
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: widget.listening ? 'Stop listening' : 'Talk to Aria',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: t.palette.primary.withValues(alpha: 0.35),
                blurRadius: 16 + 12 * _pulse.value,
                spreadRadius: 6 * _pulse.value,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: AriaTokens.micSize,
            height: AriaTokens.micSize,
            decoration: BoxDecoration(gradient: t.primaryGradient),
            child: InkWell(
              onTap: widget.onPressed,
              child: Icon(
                widget.listening ? Icons.graphic_eq : Icons.mic_rounded,
                size: 30,
                color: t.palette.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
