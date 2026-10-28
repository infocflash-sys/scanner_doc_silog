import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doc_silog/services/doc_vision.dart';
import 'package:doc_silog/services/live_detector.dart';

/// Foto sintética: suelo gris con ruido, hoja blanca inclinada con líneas de texto y
/// un degradado de sombra sobre la hoja. Devuelve la imagen y las esquinas reales (0..1).
({img.Image image, List<double> corners}) _foto({int w = 480, int h = 640}) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  final rnd = math.Random(7);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final g = 108 + rnd.nextInt(14) + (14 * math.sin(x / 40)).round();
      im.setPixelRgb(x, y, g, g, g - 3);
    }
  }
  // hoja (px): TL, TR, BR, BL
  final q = [
    img.Point(100, 150),
    img.Point(370, 138),
    img.Point(392, 470),
    img.Point(112, 486),
  ];
  img.fillPolygon(im, vertices: q, color: img.ColorRgb8(236, 236, 232));

  // texto: rectas finas en coordenadas de hoja
  img.Point lerp(img.Point a, img.Point b, double t) =>
      img.Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  img.Point at(double u, double v) => lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v);
  for (var i = 0; i < 18; i++) {
    final v = 0.12 + i * 0.045;
    final a = at(0.12, v), b = at(0.88 - (i % 4) * 0.08, v);
    img.drawLine(im, x1: a.x.round(), y1: a.y.round(), x2: b.x.round(), y2: b.y.round(),
        color: img.ColorRgb8(60, 60, 60), thickness: 3);
  }
  // sombra: oscurece la mitad derecha de la hoja
  for (var y = 0; y < h; y++) {
    for (var x = 260; x < w; x++) {
      final p = im.getPixel(x, y);
      if (p.r > 150) {
        final k = 1 - ((x - 260) / 220).clamp(0.0, 1.0) * 0.35;
        im.setPixelRgb(x, y, (p.r * k).round(), (p.g * k).round(), (p.b * k).round());
      }
    }
  }
  return (
    image: im,
    corners: [for (final p in q) ...[p.x / (w - 1), p.y / (h - 1)]],
  );
}

void main() {
  group('detectDocumentQuad', () {
    test('encuentra las 4 esquinas de la hoja (error < 3%)', () {
      final f = _foto();
      final q = detectDocumentQuad(f.image);
      expect(q, isNotNull);
      for (var i = 0; i < 8; i++) {
        expect((q![i] - f.corners[i]).abs(), lessThan(0.03), reason: 'coordenada $i');
      }
    });

    test('devuelve null si no hay hoja (imagen uniforme)', () {
      final im = img.Image(width: 300, height: 400, numChannels: 3);
      img.fill(im, color: img.ColorRgb8(120, 120, 120));
      expect(detectDocumentQuad(im), isNull);
    });
  });

  group('warpQuad + filtros', () {
    test('endereza la hoja a un rectángulo con proporción coherente', () {
      final f = _foto();
      final out = warpQuad(f.image, f.corners);
      // la hoja real mide ~280 x 340 px: relación alto/ancho ≈ 1.2
      final ratio = out.height / out.width;
      expect(ratio, inInclusiveRange(1.05, 1.4));
    });

    test('Documento: papel casi blanco (aun con sombra) y texto oscuro', () {
      final f = _foto();
      final doc = filterDocumento(warpQuad(f.image, f.corners));
      final bytes = doc.getBytes(order: img.ChannelOrder.rgb);
      var white = 0, dark = 0;
      for (var i = 0; i < bytes.length; i += 3) {
        if (bytes[i] > 235) white++;
        if (bytes[i] < 80) dark++;
      }
      final n = bytes.length / 3;
      expect(white / n, greaterThan(0.80), reason: 'el fondo debe quedar blanco');
      expect(dark / n, greaterThan(0.01), reason: 'el texto debe conservarse');
    });
  });

  group('LiveDocDetector', () {
    test('da las mismas esquinas sin importar la rotación del sensor', () {
      final f = _foto(w: 360, h: 480);
      final g = img.grayscale(f.image.clone());
      final ub = g.getBytes(order: img.ChannelOrder.rgb);
      final uw = g.width, uh = g.height;
      final up = Uint8List(uw * uh);
      for (var i = 0; i < uw * uh; i++) {
        up[i] = ub[i * 3];
      }
      final ref = LiveDocDetector.detect(up, uw, uh, 0)!;

      for (final rot in [90, 180, 270]) {
        final bool swap = rot != 180;
        final fw = swap ? uh : uw, fh = swap ? uw : uh;
        final fr = Uint8List(fw * fh);
        for (var y = 0; y < fh; y++) {
          for (var x = 0; x < fw; x++) {
            fr[y * fw + x] = switch (rot) {
              90 => up[x * uw + (fh - 1 - y)],
              270 => up[(fw - 1 - x) * uw + y],
              _ => up[(fh - 1 - y) * uw + (fw - 1 - x)],
            };
          }
        }
        final q = LiveDocDetector.detect(fr, fw, fh, rot);
        expect(q, isNotNull, reason: 'rot $rot');
        for (var i = 0; i < 8; i++) {
          expect((q!.pts[i] - ref.pts[i]).abs(), lessThan(0.02), reason: 'rot $rot, coord $i');
        }
        expect(q!.uprightW, uw);
        expect(q.uprightH, uh);
      }
    });
  });
}
