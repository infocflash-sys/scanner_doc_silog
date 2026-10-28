import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/config.dart';
import '../models/models.dart';
import 'doc_vision.dart';

class BaseInfo {
  final String path;
  final int w;
  final int h;
  const BaseInfo(this.path, this.w, this.h);
}

class _PrepJob {
  final String src, dst;
  const _PrepJob(this.src, this.dst);
}

class _Job {
  final String base, dst;
  final int filter, turns;
  final List<double>? corners;
  const _Job(this.base, this.dst, this.filter, this.turns, this.corners);
}

/// Procesamiento de páginas. Todo corre en isolates para que la UI no se congele.
class ImageService {
  /// Decodifica, corrige la orientación EXIF y limita el tamaño. Sobre este archivo
  /// "base" se calculan las esquinas y se hacen todos los procesos posteriores.
  static Future<BaseInfo> prepararBase(String src, String dst) => compute(_prep, _PrepJob(src, dst));

  /// Detecta las esquinas de la hoja en la imagen base (normalizadas) o `null`.
  static Future<List<double>?> detectar(String basePath) => compute(_detect, basePath);

  /// Recorta con perspectiva (si hay [corners]), gira y aplica el filtro. Devuelve la ruta del JPEG.
  static Future<String> procesar({
    required String basePath,
    required String dst,
    required DocFilter filter,
    required int turns,
    List<double>? corners,
  }) =>
      compute(_run, _Job(basePath, dst, filter.index, turns, corners));
}

BaseInfo _prep(_PrepJob j) {
  var im = img.decodeImage(File(j.src).readAsBytesSync());
  if (im == null) throw Exception('No se pudo leer la imagen');
  im = img.bakeOrientation(im);
  if (im.numChannels != 3) im = im.convert(numChannels: 3);

  const cap = 2600;
  final long = math.max(im.width, im.height);
  if (long > cap) {
    im = im.width >= im.height ? img.copyResize(im, width: cap) : img.copyResize(im, height: cap);
  }
  File(j.dst).writeAsBytesSync(img.encodeJpg(im, quality: 92));
  return BaseInfo(j.dst, im.width, im.height);
}

List<double>? _detect(String basePath) {
  final im = img.decodeImage(File(basePath).readAsBytesSync());
  if (im == null) return null;
  return detectDocumentQuad(im);
}

String _run(_Job j) {
  var im = img.decodeImage(File(j.base).readAsBytesSync());
  if (im == null) throw Exception('No se pudo leer la imagen');
  if (im.numChannels != 3) im = im.convert(numChannels: 3);

  if (j.corners != null) {
    im = warpQuad(im, j.corners!, maxSide: AppConfig.maxSide);
  } else {
    final long = math.max(im.width, im.height);
    if (long > AppConfig.maxSide) {
      im = im.width >= im.height
          ? img.copyResize(im, width: AppConfig.maxSide)
          : img.copyResize(im, height: AppConfig.maxSide);
    }
  }

  final t = j.turns % 4;
  if (t != 0) im = img.copyRotate(im, angle: 90 * t);

  switch (DocFilter.values[j.filter]) {
    case DocFilter.original:
      break;
    case DocFilter.documento:
      im = filterDocumento(im);
    case DocFilter.gris:
      im = filterGris(im);
    case DocFilter.color:
      im = filterColor(im);
  }

  File(j.dst).writeAsBytesSync(img.encodeJpg(im, quality: AppConfig.jpegQuality));
  return j.dst;
}
