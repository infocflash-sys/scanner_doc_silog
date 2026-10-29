import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Aro giratorio de [total] barritas: una por página a procesar. Las [done] primeras se encienden
/// (degradado verde → turquesa) y la siguiente late mientras se procesa.
class SegmentRing extends StatefulWidget {
  final int total;
  final int done;
  final double size;
  const SegmentRing({super.key, required this.total, required this.done, this.size = 44});

  @override
  State<SegmentRing> createState() => _SegmentRingState();
}

class _SegmentRingState extends State<SegmentRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _RingPainter(widget.total, widget.done, _c.value),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int total;
  final int done;
  final double t; // 0..1 vuelta completa

  _RingPainter(this.total, this.done, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.58;
    final mid = (outer + inner) / 2;
    final stroke = math.min(outer * 0.28, (2 * math.pi * mid) / (total * 2.3));
    final pulse = 0.55 + 0.45 * math.sin(t * 2 * math.pi * 6); // latido de la barrita en curso

    for (var i = 0; i < total; i++) {
      final a = -math.pi / 2 + (2 * math.pi * i / total) + t * 2 * math.pi;
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke;
      if (i < done) {
        p.color = Color.lerp(Brand.green, Brand.teal, total <= 1 ? 0 : i / (total - 1))!;
      } else if (i == done) {
        p.color = Brand.green.withValues(alpha: pulse);
      } else {
        p.color = Brand.border;
      }
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * outer,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.total != total || o.done != done || o.t != t;
}
