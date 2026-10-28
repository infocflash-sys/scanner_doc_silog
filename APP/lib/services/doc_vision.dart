import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Visión por computadora para documentos, en Dart puro (corre en un isolate):
/// detección de la hoja, corrección de perspectiva y filtros de legibilidad.
///
/// Las esquinas se expresan normalizadas (0..1) como [x0,y0, x1,y1, x2,y2, x3,y3]
/// en el orden: arriba-izq, arriba-der, abajo-der, abajo-izq.

// ───────────────────────── Detección ─────────────────────────

/// Busca la hoja de papel (la región clara más grande cerca del centro) y devuelve sus
/// 4 esquinas, o `null` si no hay un cuadrilátero creíble.
List<double>? detectDocumentQuad(img.Image src) {
  final long = math.max(src.width, src.height);
  final k = long > 480 ? 480 / long : 1.0;
  var small = k < 1
      ? img.copyResize(
          src,
          width: (src.width * k).round(),
          height: (src.height * k).round(),
          interpolation: img.Interpolation.average,
        )
      : src.clone();
  small = img.grayscale(small);
  small = img.gaussianBlur(small, radius: 5);

  final w = small.width, h = small.height;
  final rgb = small.getBytes(order: img.ChannelOrder.rgb);
  final lum = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    lum[i] = rgb[i * 3];
  }

  return _quadFromLum(lum, w, h);
}

/// Variante para frames de cámara en vivo: recibe la luminancia ya orientada (derecha) y
/// devuelve las esquinas normalizadas, o `null`. Aplica un desenfoque de caja pequeño.
List<double>? detectQuadFromLuma(Uint8List lum, int w, int h) {
  return _quadFromLum(_boxBlur(lum, w, h, 2), w, h);
}

Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(src.length);
  final out = Uint8List(src.length);
  final win = 2 * r + 1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += src[row + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum ~/ win;
      sum += src[row + (x + r + 1).clamp(0, w - 1)] - src[row + (x - r).clamp(0, w - 1)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum ~/ win;
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] - tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  return out;
}

/// Núcleo: umbral de Otsu, componente clara central y extremos en las diagonales.
List<double>? _quadFromLum(Uint8List lum, int w, int h) {
  final th = _otsu(lum);

  // Polaridad: el papel debe ser la región clara, salvo que el centro sea claramente oscuro.
  var above = 0, total = 0;
  for (var y = (h * 0.35).round(); y < (h * 0.65).round(); y++) {
    for (var x = (w * 0.35).round(); x < (w * 0.65).round(); x++) {
      total++;
      if (lum[y * w + x] > th) above++;
    }
  }
  final invert = total > 0 && above / total < 0.25;

  final mask = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    mask[i] = ((lum[i] > th) != invert) ? 1 : 0;
  }

  // Componentes conexas (4-vecinos)
  final labels = Int32List(w * h);
  final stack = Int32List(w * h);
  final sizes = <int>[0];
  var next = 0;
  for (var i = 0; i < w * h; i++) {
    if (mask[i] == 0 || labels[i] != 0) continue;
    next++;
    var sp = 0, size = 0;
    stack[sp++] = i;
    labels[i] = next;
    while (sp > 0) {
      final p = stack[--sp];
      size++;
      final x = p % w, y = p ~/ w;
      if (x > 0 && mask[p - 1] == 1 && labels[p - 1] == 0) {
        labels[p - 1] = next;
        stack[sp++] = p - 1;
      }
      if (x < w - 1 && mask[p + 1] == 1 && labels[p + 1] == 0) {
        labels[p + 1] = next;
        stack[sp++] = p + 1;
      }
      if (y > 0 && mask[p - w] == 1 && labels[p - w] == 0) {
        labels[p - w] = next;
        stack[sp++] = p - w;
      }
      if (y < h - 1 && mask[p + w] == 1 && labels[p + w] == 0) {
        labels[p + w] = next;
        stack[sp++] = p + w;
      }
    }
    sizes.add(size);
  }
  if (next == 0) return null;

  // Componente elegida: la del centro si es grande; si no, la más grande.
  var chosen = 0;
  final cx = w ~/ 2, cy = h ~/ 2;
  final maxR = (math.min(w, h) * 0.2).round();
  search:
  for (var r = 0; r <= maxR; r += 2) {
    for (var dy = -r; dy <= r; dy += 2) {
      for (var dx = -r; dx <= r; dx += 2) {
        if (dx.abs() != r && dy.abs() != r) continue;
        final x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        final l = labels[y * w + x];
        if (l != 0) {
          chosen = l;
          break search;
        }
      }
    }
  }
  if (chosen == 0 || sizes[chosen] < w * h * 0.10) {
    var best = 0;
    for (var l = 1; l < sizes.length; l++) {
      if (sizes[l] > best) {
        best = sizes[l];
        chosen = l;
      }
    }
  }
  if (chosen == 0 || sizes[chosen] < w * h * 0.06) return null;

  // Esquinas = puntos extremos de la región en las dos diagonales.
  var tlS = 1 << 30, brS = -(1 << 30), trD = -(1 << 30), blD = 1 << 30;
  var tl = const [0, 0], br = const [0, 0], tr = const [0, 0], bl = const [0, 0];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (labels[y * w + x] != chosen) continue;
      final s = x + y, d = x - y;
      if (s < tlS) {
        tlS = s;
        tl = [x, y];
      }
      if (s > brS) {
        brS = s;
        br = [x, y];
      }
      if (d > trD) {
        trD = d;
        tr = [x, y];
      }
      if (d < blD) {
        blD = d;
        bl = [x, y];
      }
    }
  }

  final pts = <List<double>>[
    [tl[0].toDouble(), tl[1].toDouble()],
    [tr[0].toDouble(), tr[1].toDouble()],
    [br[0].toDouble(), br[1].toDouble()],
    [bl[0].toDouble(), bl[1].toDouble()],
  ];

  // Validaciones: convexo, área razonable y que la región llene el cuadrilátero.
  final area = _polyArea(pts);
  final frac = area / (w * h);
  if (frac < 0.08 || frac > 0.985) return null;
  if (sizes[chosen] / area < 0.55) return null;
  if (!_isConvex(pts)) return null;
  final minSide = 0.12 * math.max(w, h);
  for (var i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    if (math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2)) < minSide) return null;
  }

  final out = <double>[];
  for (final p in pts) {
    out.add((p[0] / (w - 1)).clamp(0.0, 1.0));
    out.add((p[1] / (h - 1)).clamp(0.0, 1.0));
  }
  return out;
}

int _otsu(Uint8List lum) {
  final hist = List<int>.filled(256, 0);
  for (final v in lum) {
    hist[v]++;
  }
  final total = lum.length;
  var sum = 0.0;
  for (var t = 0; t < 256; t++) {
    sum += t * hist[t];
  }
  var sumB = 0.0, maxVar = -1.0;
  var wB = 0, th = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final v = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (v > maxVar) {
      maxVar = v;
      th = t;
    }
  }
  return th;
}

double _polyArea(List<List<double>> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final q = p[(i + 1) % p.length];
    a += p[i][0] * q[1] - q[0] * p[i][1];
  }
  return a.abs() / 2;
}

bool _isConvex(List<List<double>> p) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
    final cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
    if (cross.abs() < 1e-6) continue;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

// ───────────────────────── Perspectiva ─────────────────────────

/// Endereza el cuadrilátero [c] (normalizado) a un rectángulo, con interpolación bilineal.
/// El lado mayor de la salida se limita a [maxSide].
img.Image warpQuad(img.Image src, List<double> c, {int maxSide = 2200, double inset = 0.004}) {
  final sw = src.width, sh = src.height;
  final x = [for (var i = 0; i < 4; i++) c[i * 2] * (sw - 1)];
  final y = [for (var i = 0; i < 4; i++) c[i * 2 + 1] * (sh - 1)];

  double dist(int a, int b) => math.sqrt(math.pow(x[a] - x[b], 2) + math.pow(y[a] - y[b], 2));

  var ow = math.max(dist(0, 1), dist(3, 2));
  var oh = math.max(dist(0, 3), dist(1, 2));
  final big = math.max(ow, oh);
  if (big > maxSide) {
    ow *= maxSide / big;
    oh *= maxSide / big;
  }
  final outW = math.max(16, ow.round()), outH = math.max(16, oh.round());

  // Homografía cuadrado unidad → cuadrilátero (Heckbert)
  final sx = x[0] - x[1] + x[2] - x[3];
  final sy = y[0] - y[1] + y[2] - y[3];
  double g, hh;
  if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
    g = 0;
    hh = 0;
  } else {
    final dx1 = x[1] - x[2], dx2 = x[3] - x[2];
    final dy1 = y[1] - y[2], dy2 = y[3] - y[2];
    final den = dx1 * dy2 - dx2 * dy1;
    g = (sx * dy2 - dx2 * sy) / den;
    hh = (dx1 * sy - sx * dy1) / den;
  }
  final a = x[1] - x[0] + g * x[1];
  final b = x[3] - x[0] + hh * x[3];
  final cc = x[0];
  final d = y[1] - y[0] + g * y[1];
  final e = y[3] - y[0] + hh * y[3];
  final f = y[0];

  final s = src.numChannels == 3 ? src : src.convert(numChannels: 3);
  final sb = s.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(outW * outH * 3);
  final maxX = sw - 1.001, maxY = sh - 1.001;

  for (var j = 0; j < outH; j++) {
    final v = inset + (j + 0.5) / outH * (1 - 2 * inset);
    for (var i = 0; i < outW; i++) {
      final u = inset + (i + 0.5) / outW * (1 - 2 * inset);
      final den = g * u + hh * v + 1.0;
      var px = (a * u + b * v + cc) / den;
      var py = (d * u + e * v + f) / den;
      if (px < 0) px = 0;
      if (py < 0) py = 0;
      if (px > maxX) px = maxX;
      if (py > maxY) py = maxY;
      final x0 = px.toInt(), y0 = py.toInt();
      final fx = px - x0, fy = py - y0;
      final i00 = (y0 * sw + x0) * 3;
      final i10 = i00 + 3;
      final i01 = i00 + sw * 3;
      final i11 = i01 + 3;
      final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
      final o = (j * outW + i) * 3;
      out[o] = (sb[i00] * w00 + sb[i10] * w10 + sb[i01] * w01 + sb[i11] * w11).round();
      out[o + 1] = (sb[i00 + 1] * w00 + sb[i10 + 1] * w10 + sb[i01 + 1] * w01 + sb[i11 + 1] * w11).round();
      out[o + 2] = (sb[i00 + 2] * w00 + sb[i10 + 2] * w10 + sb[i01 + 2] * w01 + sb[i11 + 2] * w11).round();
    }
  }
  return img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

// ───────────────────────── Filtros ─────────────────────────

/// Estima la iluminación del papel: sobre una versión reducida aplica un filtro de máximo
/// (que elimina texto y fotos oscuras, dejando solo el nivel del papel) y lo suaviza.
/// Devuelve el fondo a tamaño completo como bytes RGB.
Uint8List _background(img.Image im) {
  final w = im.width, h = im.height;
  var small = img.copyResize(
    im,
    width: math.max(48, (w / 6).round()),
    interpolation: img.Interpolation.average,
  );
  if (small.numChannels != 3) small = small.convert(numChannels: 3);
  final sw = small.width, sh = small.height;
  final data = small.getBytes(order: img.ChannelOrder.rgb);
  final r = math.max(4, (math.min(sw, sh) * 0.09).round());
  final dil = _dilate(data, sw, sh, r);
  final soft = img.gaussianBlur(_fromRgb(dil, sw, sh), radius: math.max(4, r ~/ 2));
  final bg = img.copyResize(soft, width: w, height: h, interpolation: img.Interpolation.linear);
  return (bg.numChannels == 3 ? bg : bg.convert(numChannels: 3)).getBytes(order: img.ChannelOrder.rgb);
}

/// Filtro de máximo separable (radio [r]) sobre una imagen RGB entrelazada.
Uint8List _dilate(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r), x1 = math.min(w - 1, x + r);
      for (var c = 0; c < 3; c++) {
        var m = 0;
        for (var k = x0; k <= x1; k++) {
          final v = src[(y * w + k) * 3 + c];
          if (v > m) m = v;
        }
        tmp[(y * w + x) * 3 + c] = m;
      }
    }
  }
  final out = Uint8List(src.length);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h - 1, y + r);
      for (var c = 0; c < 3; c++) {
        var m = 0;
        for (var k = y0; k <= y1; k++) {
          final v = tmp[(k * w + x) * 3 + c];
          if (v > m) m = v;
        }
        out[(y * w + x) * 3 + c] = m;
      }
    }
  }
  return out;
}

img.Image _fromRgb(Uint8List bytes, int w, int h) => img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );

Uint8List _rgb(img.Image im) =>
    (im.numChannels == 3 ? im : im.convert(numChannels: 3)).getBytes(order: img.ChannelOrder.rgb);

/// "Documento": blanco y negro nítido. Quita sombras y degradados de luz dividiendo entre el
/// fondo estimado, fija el negro del texto y el blanco del papel, y afila los trazos.
img.Image filterDocumento(img.Image src) {
  final w = src.width, h = src.height;
  final gray = img.grayscale(src.clone());
  final g = _rgb(gray);
  final bg = _background(gray);

  const black = 100.0, white = 228.0;
  final lum = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final b = math.max(1, bg[i * 3]);
    final norm = g[i * 3] / b * 255.0;
    final v = ((norm - black) / (white - black)).clamp(0.0, 1.0);
    // Curva suave: oscurece el texto sin quemar los trazos finos.
    lum[i] = (255 * (v * v * (3 - 2 * v))).round();
  }
  _sharpen(lum, w, h, 0.6);

  final out = Uint8List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = lum[i];
  }
  return _fromRgb(out, w, h);
}

/// "Gris": escala de grises con rango dinámico completo y algo de nitidez.
img.Image filterGris(img.Image src) {
  final w = src.width, h = src.height;
  var gray = img.grayscale(src.clone());
  gray = img.normalize(gray, min: 0, max: 255);
  final g = _rgb(gray);
  final lum = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    lum[i] = g[i * 3];
  }
  _sharpen(lum, w, h, 0.5);
  final out = Uint8List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = lum[i];
  }
  return _fromRgb(out, w, h);
}

/// "Color+": conserva los colores pero uniforma la iluminación, blanquea el papel y sube el contraste.
img.Image filterColor(img.Image src) {
  final w = src.width, h = src.height;
  final s = _rgb(src);
  final bg = _background(src);
  final out = Uint8List(w * h * 3);
  const black = 35.0, white = 235.0;
  for (var i = 0; i < w * h * 3; i++) {
    final b = math.max(1, bg[i]);
    final norm = s[i] / b * 245.0;
    out[i] = (((norm - black) / (white - black)).clamp(0.0, 1.0) * 255).round();
  }
  return img.adjustColor(_fromRgb(out, w, h), saturation: 1.12);
}

/// Máscara de enfoque 3×3 (laplaciano de 4 vecinos) sobre un canal de luminancia.
void _sharpen(Uint8List l, int w, int h, double amount) {
  final copy = Uint8List.fromList(l);
  for (var y = 1; y < h - 1; y++) {
    final row = y * w;
    for (var x = 1; x < w - 1; x++) {
      final i = row + x;
      final lap = 4 * copy[i] - copy[i - 1] - copy[i + 1] - copy[i - w] - copy[i + w];
      final v = copy[i] + amount * lap;
      l[i] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
    }
  }
}
