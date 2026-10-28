import 'dart:math' as math;
import 'dart:typed_data';

import 'doc_vision.dart';

/// Esquinas detectadas en un frame de cámara, normalizadas sobre la imagen ya orientada
/// (derecha): TL, TR, BR, BL; más el tamaño de esa imagen a resolución del frame.
class LiveQuad {
  final List<double> pts; // x0,y0,...,x3,y3 en 0..1
  final int uprightW;
  final int uprightH;
  const LiveQuad(this.pts, this.uprightW, this.uprightH);
}

class LiveDocDetector {
  /// [y] es el plano de luminancia del frame (NV21/YUV: los primeros w*h bytes), tal como lo
  /// entrega el sensor. [rotation] son los grados (0/90/180/270) que hay que girar el frame
  /// en sentido horario para que quede derecho.
  static LiveQuad? detect(Uint8List y, int w, int h, int rotation) {
    if (y.length < w * h) return null;

    // Reduce a ~250 px de lado mayor (vecino más cercano; luego se suaviza).
    final step = math.max(1, (math.max(w, h) / 250).round());
    final sw = w ~/ step, sh = h ~/ step;
    if (sw < 16 || sh < 16) return null;

    final int uw, uh;
    switch (rotation) {
      case 90:
      case 270:
        uw = sh;
        uh = sw;
      default:
        uw = sw;
        uh = sh;
    }

    final up = Uint8List(uw * uh);
    for (var yy = 0; yy < sh; yy++) {
      final srcRow = (yy * step) * w;
      for (var xx = 0; xx < sw; xx++) {
        final v = y[srcRow + xx * step];
        final int ux, uy;
        switch (rotation) {
          case 90:
            ux = sh - 1 - yy;
            uy = xx;
          case 270:
            ux = yy;
            uy = sw - 1 - xx;
          case 180:
            ux = sw - 1 - xx;
            uy = sh - 1 - yy;
          default:
            ux = xx;
            uy = yy;
        }
        up[uy * uw + ux] = v;
      }
    }

    final q = detectQuadFromLuma(up, uw, uh);
    if (q == null) return null;

    final fullW = (rotation == 90 || rotation == 270) ? h : w;
    final fullH = (rotation == 90 || rotation == 270) ? w : h;
    return LiveQuad(q, fullW, fullH);
  }
}
