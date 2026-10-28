import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Animación de bienvenida que cuenta lo que hace la app:
/// una hoja fotografiada en ángulo → se detectan sus bordes → se endereza →
/// un haz la escanea y la "mejora" de arriba hacia abajo → check de listo.
///
/// [t] va de 0 a 1.
class ScanIntroPainter extends CustomPainter {
  final double t;
  const ScanIntroPainter(this.t);

  static const sheetW = 188.0;
  static const sheetH = 244.0;

  double _seg(double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final fade = _seg(0.0, 0.12);
    final appear = _seg(0.0, 0.22, Curves.easeOutBack);
    final bracket = _seg(0.18, 0.45, Curves.easeOutCubic);
    final straighten = _seg(0.30, 0.55, Curves.easeInOutCubic);
    final beam = _seg(0.50, 0.86, Curves.easeInOutCubic);
    final badge = _seg(0.86, 1.0, Curves.elasticOut);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(0.72 + 0.28 * appear);
    canvas.rotate(lerpDouble(0.17, 0.0, straighten)!);

    final rect = Rect.fromCenter(center: Offset.zero, width: sheetW, height: sheetH);

    canvas.saveLayer(rect.inflate(160), Paint()..color = Colors.white.withValues(alpha: fade));

    // Capa base: la "foto cruda" (gris, sin contraste).
    _sheet(canvas, rect, enhanced: false);

    // Capa mejorada: solo por encima del haz.
    final beamY = lerpDouble(rect.top - 10, rect.bottom + 10, beam)!;
    if (beam > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(rect.left - 6, rect.top - 6, rect.right + 6, beamY));
      _sheet(canvas, rect, enhanced: true);
      canvas.restore();
    }

    _brackets(canvas, rect, bracket, done: beam >= 1 ? 1.0 : 0.0);
    if (beam > 0 && beam < 1) _beam(canvas, rect, beamY, beam);
    if (badge > 0) _badge(canvas, rect, badge);

    canvas.restore(); // saveLayer
    canvas.restore();
  }

  void _sheet(Canvas canvas, Rect r, {required bool enhanced}) {
    const fold = 42.0;
    final path = Path()
      ..moveTo(r.left + 14, r.top)
      ..lineTo(r.right - fold, r.top)
      ..lineTo(r.right, r.top + fold)
      ..lineTo(r.right, r.bottom - 14)
      ..quadraticBezierTo(r.right, r.bottom, r.right - 14, r.bottom)
      ..lineTo(r.left + 14, r.bottom)
      ..quadraticBezierTo(r.left, r.bottom, r.left, r.bottom - 14)
      ..lineTo(r.left, r.top + 14)
      ..quadraticBezierTo(r.left, r.top, r.left + 14, r.top)
      ..close();

    if (!enhanced) {
      canvas.drawShadow(path, Colors.black, 22, false);
    }

    canvas.drawPath(path, Paint()..color = enhanced ? Colors.white : const Color(0xFFC3CBDB));

    final foldPath = Path()
      ..moveTo(r.right - fold, r.top)
      ..lineTo(r.right, r.top + fold)
      ..lineTo(r.right - fold, r.top + fold)
      ..close();
    canvas.drawPath(
      foldPath,
      Paint()..color = enhanced ? const Color(0xFFCDEBDD) : const Color(0xFFA9B3C8),
    );

    // Líneas de texto
    const widths = [0.50, 1.0, 1.0, 0.86, 1.0, 0.72, 0.46];
    final left = r.left + 20;
    final full = r.width - 40;
    var y = r.top + 78;
    for (var i = 0; i < widths.length; i++) {
      final thick = i == 0 ? 12.0 : 8.5;
      final w = full * widths[i];
      final line = RRect.fromLTRBR(left, y, left + w, y + thick, Radius.circular(thick / 2));
      if (enhanced) {
        canvas.drawRRect(
          line,
          Paint()
            ..shader = const LinearGradient(colors: [Brand.green, Brand.teal])
                .createShader(Rect.fromLTWH(left, y, full, thick)),
        );
      } else {
        // Texto "borroso": más claro y con un pequeño desfase, como una foto movida.
        canvas.drawRRect(
          line.shift(Offset(i.isEven ? 1.5 : -1.5, 0.5)),
          Paint()
            ..color = const Color(0xFF8E99B2).withValues(alpha: 0.75)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
        );
      }
      y += 24;
    }
  }

  void _brackets(Canvas canvas, Rect rect, double p, {required double done}) {
    if (p <= 0) return;
    final m = lerpDouble(70, 16, p)!;
    final r = rect.inflate(m);
    const len = 36.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Brand.green, Brand.teal],
      ).createShader(r);

    if (done > 0 || p > 0.6) {
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Brand.green.withValues(alpha: 0.18 * math.min(1, p)),
      );
    }

    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: math.min(1, p * 1.6)));
    final path = Path()
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + len, r.top)
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + len)
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - len, r.bottom)
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - len);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _beam(Canvas canvas, Rect rect, double y, double p) {
    final edge = math.min(1.0, math.min(p, 1 - p) * 8);
    final left = rect.left - 30;
    final right = rect.right + 30;

    // Estela luminosa detrás del haz
    final trail = Rect.fromLTRB(left, y - 90, right, y);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Brand.green.withValues(alpha: 0),
            Brand.green.withValues(alpha: 0.30 * edge),
          ],
        ).createShader(trail),
    );

    // Resplandor y línea del haz
    final bar = RRect.fromLTRBR(left, y - 2.5, right, y + 2.5, const Radius.circular(3));
    canvas.drawRRect(
      bar,
      Paint()
        ..color = Brand.green.withValues(alpha: 0.9 * edge)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..shader = LinearGradient(colors: [
          Brand.green.withValues(alpha: 0),
          Colors.white.withValues(alpha: edge),
          Brand.teal.withValues(alpha: 0),
        ]).createShader(Rect.fromLTRB(left, y - 3, right, y + 3)),
    );
  }

  void _badge(Canvas canvas, Rect rect, double p) {
    final c = rect.bottomRight + const Offset(16, 16);
    final r = 27.0 * p;
    canvas.drawCircle(
      c,
      r + 6,
      Paint()
        ..color = Brand.green.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Brand.gradient.createShader(Rect.fromCircle(center: c, radius: math.max(r, 1))),
    );
    final k = p.clamp(0.0, 1.0);
    final check = Path()
      ..moveTo(c.dx - 11 * k, c.dy + 0.5 * k)
      ..lineTo(c.dx - 3 * k, c.dy + 8.5 * k)
      ..lineTo(c.dx + 12 * k, c.dy - 8 * k);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(ScanIntroPainter old) => old.t != t;
}
