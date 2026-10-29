import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config.dart';

/// Resultado de armar el PDF (para informar al operador antes de subirlo).
class PdfBuild {
  final File file;
  final int bytes;
  final int pages;
  final bool reducido; // alguna página se redujo para ajustarse al límite
  final bool forzado; // hubo que bajar la calidad más de lo habitual
  const PdfBuild(this.file, this.bytes, this.pages, {this.reducido = false, this.forzado = false});
}

/// El PDF supera el límite de subida incluso con la reducción máxima.
class PdfTooLargeException implements Exception {
  final int bytes;
  final int pages;
  const PdfTooLargeException(this.bytes, this.pages);
}

class _FitJob {
  final List<String> paths;
  final String tmp;
  final int pageBudget;
  final int limit;
  const _FitJob(this.paths, this.tmp, this.pageBudget, this.limit);
}

class _FitOut {
  final List<String> paths;
  final bool reducido;
  final bool forzado;
  const _FitOut(this.paths, this.reducido, this.forzado);
}

/// (lado mayor en px, calidad JPEG), de más a menos pesado. El PDF embebe los JPEG tal cual,
/// así que su tamaño es ~ la suma de las páginas.
/// Piso de 1000 px / calidad 58 (~85 dpi en A4): solo se llega ahí con muchas páginas.
const _levels = <(int, int)>[
  (2100, 84), (2000, 80), (1850, 76), (1700, 72), (1550, 68), (1400, 65), (1300, 63), (1200, 62),
  (1100, 60), (1000, 58),
];

/// Reducción forzada: solo si el total sigue pasando el límite tras agotar [_levels].
/// Sacrifica calidad (el texto sigue siendo legible, pero más blando).
const _forced = <(int, int)>[(900, 52), (800, 46), (700, 40), (600, 35)];

/// Reduce [im] con cada nivel de [levels] hasta que quepa en [budget]; devuelve los bytes del último intento.
List<int> _shrink(img.Image im, List<(int, int)> levels, int budget) {
  final long = math.max(im.width, im.height);
  List<int> bytes = const [];
  for (final (side, q) in levels) {
    final cur = long > side
        ? (im.width >= im.height ? img.copyResize(im, width: side) : img.copyResize(im, height: side))
        : im;
    bytes = img.encodeJpg(cur, quality: q);
    if (bytes.length <= budget) break;
  }
  return bytes;
}

/// Devuelve las rutas a usar en el PDF. Las páginas que ya pesan <= [_FitJob.pageBudget] se dejan
/// intactas. Si el total sigue pasando [_FitJob.limit], se fuerza una reducción mayor.
_FitOut _fit(_FitJob j) {
  final out = List<String>.of(j.paths);
  final sizes = List<int>.generate(j.paths.length, (i) => File(j.paths[i]).lengthSync());
  var reducido = false, forzado = false;

  for (var i = 0; i < j.paths.length; i++) {
    if (sizes[i] <= j.pageBudget) continue;
    var im = img.decodeImage(File(j.paths[i]).readAsBytesSync());
    if (im == null) continue;
    if (im.numChannels != 3) im = im.convert(numChannels: 3);
    final bytes = _shrink(im, _levels, j.pageBudget);
    final dst = '${j.tmp}/pg_fit_$i.jpg';
    File(dst).writeAsBytesSync(bytes);
    out[i] = dst;
    sizes[i] = bytes.length;
    reducido = true;
  }

  if (sizes.fold(0, (s, b) => s + b) > j.limit) {
    for (var i = 0; i < j.paths.length; i++) {
      if (sizes[i] <= j.pageBudget) continue;
      var im = img.decodeImage(File(j.paths[i]).readAsBytesSync());
      if (im == null) continue;
      if (im.numChannels != 3) im = im.convert(numChannels: 3);
      final bytes = _shrink(im, _forced, j.pageBudget);
      final dst = '${j.tmp}/pg_fit_$i.jpg';
      File(dst).writeAsBytesSync(bytes);
      out[i] = dst;
      sizes[i] = bytes.length;
      forzado = true;
    }
  }
  return _FitOut(out, reducido, forzado);
}

class PdfService {
  /// Arma un PDF A4 con una página por imagen (orientación según la imagen).
  /// Lanza [PdfTooLargeException] si, aun reducido al máximo, supera el límite de subida.
  static Future<PdfBuild> build(String idPieza, List<String> paths) async {
    final doc = pw.Document(
      compress: true,
      title: 'Documentación pieza $idPieza',
      author: 'SILOG',
      creator: 'Doc SILOG',
    );

    final tmp = (await getTemporaryDirectory()).path;
    final limit = AppConfig.maxPdfBytes;
    // 3 % de margen para la estructura del PDF; el tope por página se reparte entre las páginas.
    final budget = math.min(AppConfig.maxPageBytes, (limit * 0.97) ~/ paths.length);
    final fit = await compute(_fit, _FitJob(paths, tmp, budget, limit));

    for (final p in fit.paths) {
      final bytes = await File(p).readAsBytes();
      final size = await _size(bytes);
      final landscape = size.width > size.height;
      final image = pw.MemoryImage(bytes);

      doc.addPage(
        pw.Page(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final file = File('$tmp/$idPieza.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    final total = await file.length();
    if (total > limit) {
      await file.delete();
      throw PdfTooLargeException(total, paths.length);
    }
    return PdfBuild(file, total, paths.length, reducido: fit.reducido, forzado: fit.forzado);
  }

  static Future<ui.Size> _size(Uint8List bytes) async {
    final data = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(data);
    final s = ui.Size(desc.width.toDouble(), desc.height.toDouble());
    desc.dispose();
    data.dispose();
    return s;
  }
}
