import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../talk/talk_controller.dart';
import 'theme.dart';

class TalkOrb extends StatefulWidget {
  const TalkOrb({
    super.key,
    required this.phase,
    required this.level,
    required this.reducedMotion,
    this.size = 240,
  });

  final TalkPhase phase;
  final double level;
  final bool reducedMotion;
  final double size;

  @override
  State<TalkOrb> createState() => _TalkOrbState();
}

class _TalkOrbState extends State<TalkOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _active =>
      !widget.reducedMotion &&
      (widget.phase == TalkPhase.speaking ||
          widget.phase == TalkPhase.thinking ||
          widget.level > 0.02);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 7));
    if (_active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant TalkOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _OrbPainter(
                t: widget.reducedMotion ? 0 : _controller.value,
                level: widget.level.clamp(0.0, 1.0),
                phase: widget.phase,
                teal: c.teal,
                mint: c.mint,
                warm: c.warm,
                dark: c.isDark,
                backdrop: c.canvas,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.level,
    required this.phase,
    required this.teal,
    required this.mint,
    required this.warm,
    required this.dark,
    required this.backdrop,
  });

  final double t;
  final double level;
  final TalkPhase phase;
  final Color teal;
  final Color mint;
  final Color warm;
  final bool dark;
  final Color backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide;
    final speaking = phase == TalkPhase.speaking;
    final thinking = phase == TalkPhase.thinking;
    final pulse = speaking ? 1 + math.sin(t * math.pi * 2) * 0.035 : 1.0;
    final radius = base * (0.255 + level * 0.05) * pulse;

    final glowRect = Rect.fromCircle(center: center, radius: radius * 2.05);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          teal.withValues(alpha: dark ? 0.22 : 0.15),
          teal.withValues(alpha: 0.06),
          backdrop.withValues(alpha: 0),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(glowRect);
    canvas.drawCircle(center, radius * 2.05, glow);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = teal.withValues(alpha: dark ? 0.22 : 0.16);
    canvas.drawCircle(center, radius * 1.18, halo);
    canvas.drawCircle(
      center,
      radius * 1.32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = teal.withValues(alpha: dark ? 0.10 : 0.08),
    );

    canvas.save();
    final blobPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, base * 0.045);
    for (var i = 0; i < 3; i++) {
      final drift = t * math.pi * 2 * (i.isEven ? 1 : -1);
      final wobble = 0.026 + level * 0.055 + (speaking ? 0.018 : 0) + (thinking ? 0.010 : 0);
      final path = Path();
      const points = 28;
      for (var p = 0; p <= points; p++) {
        final angle = (p / points) * math.pi * 2;
        final variation =
            1 + wobble * math.sin(angle * 3 + drift + i * 1.7) + wobble * 0.55 * math.cos(angle * 5 - drift);
        final r = radius * (0.87 + i * 0.052) * variation;
        final point = Offset(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
        if (p == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      final color = i == 0
          ? Color.lerp(mint, teal, 0.35)!
          : i == 1
              ? (dark ? teal.withValues(alpha: 0.72) : teal.withValues(alpha: 0.90))
              : Color.lerp(warm, teal, 0.45)!;
      blobPaint.color = color.withValues(alpha: i == 0 ? 0.58 : 0.32);
      canvas.drawPath(path, blobPaint);
    }
    canvas.restore();

    final coreRect = Rect.fromCircle(center: center, radius: radius * 0.88);
    final core = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.32, -0.36),
        radius: 0.9,
        colors: [
          Color.lerp(mint, Colors.white, dark ? 0.30 : 0.58)!,
          mint,
          teal,
        ],
        stops: const [0, 0.42, 1],
      ).createShader(coreRect);
    canvas.drawCircle(center, radius * 0.78, core);

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.20 : 0.42)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, base * 0.02);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - radius * 0.24, center.dy - radius * 0.32),
        width: radius * 0.68,
        height: radius * 0.36,
      ),
      highlight,
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = teal.withValues(alpha: dark ? 0.30 : 0.17);
    canvas.drawCircle(center, radius * 0.78, rim);

    if (phase == TalkPhase.thinking) {
      final orbit = radius * 0.98;
      for (var i = 0; i < 3; i++) {
        final angle = t * math.pi * 2 + (i * math.pi * 2 / 3);
        final dot = Offset(center.dx + math.cos(angle) * orbit, center.dy + math.sin(angle) * orbit);
        canvas.drawCircle(
          dot,
          base * 0.010,
          Paint()..color = teal.withValues(alpha: dark ? 0.55 : 0.38),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t ||
      old.level != level ||
      old.phase != phase ||
      old.teal != teal ||
      old.mint != mint ||
      old.warm != warm ||
      old.dark != dark;
}
