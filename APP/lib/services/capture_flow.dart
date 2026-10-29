import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../screens/crop_screen.dart';
import '../screens/live_scan_screen.dart';
import 'image_service.dart';
import 'scan_service.dart';

/// Identificadores únicos de página (también los usan los archivos temporales).
class PageIds {
  static int _n = 0;
  static int next() => _n++;
}

/// Procesa UNA foto: la prepara, deja que el usuario ubique las 4 esquinas con el dedo y, al
/// confirmar, recorta/endereza exactamente con esas esquinas y aplica el filtro de documento.
/// Devuelve la página terminada, o `null` si el usuario pidió volver a tomarla o cancelar.
Future<ScanPage?> procesarFoto(
  BuildContext context,
  String src, {
  int total = 1,
  int done = 0,
}) async {
  final tmp = (await getTemporaryDirectory()).path;
  final id = PageIds.next();

  final BaseInfo base;
  try {
    base = await ImageService.prepararBase(src, '$tmp/base_$id.jpg');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo leer la imagen. Intenta de nuevo.')),
      );
    }
    return null;
  }
  if (!context.mounted) return null;

  final r = await Navigator.of(context).push<CropResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CropScreen(
        basePath: base.path,
        width: base.w,
        height: base.h,
        title: 'Ubica las esquinas',
        confirmLabel: 'Confirmar y procesar',
        allowRetake: true,
        autoOnOpen: true,
        batchTotal: total,
        batchDone: done,
        processor: (corners) => ImageService.procesar(
          basePath: base.path,
          dst: '$tmp/pg_${id}_${DateTime.now().microsecondsSinceEpoch}.jpg',
          filter: DocFilter.documento,
          turns: 0,
          corners: corners,
        ),
      ),
    ),
  );

  if (r == null || r.retake || r.outPath == null) {
    try {
      File(base.path).deleteSync();
    } catch (_) {}
    return null;
  }

  final page = ScanPage(id: id, src: src, autoDetect: false)
    ..bw = base.w
    ..bh = base.h
    ..base = base.path
    ..out = r.outPath!
    ..corners = r.corners;
  return page;
}

/// Flujo común de captura. Devuelve las páginas YA procesadas o `null` si el usuario canceló.
///
/// - Escanear: cámara con disparador manual; cada foto pasa por la ubicación de esquinas y se
///   procesa al instante.
/// - Galería: el usuario elige fotos y cada una pasa por el mismo paso, una por una.
Future<List<ScanPage>?> capturar(
  BuildContext context, {
  required int limit,
  bool galeria = false,
}) async {
  try {
    if (galeria) {
      final paths = await ScanService.pickFromGallery(limit: limit);
      final pages = <ScanPage>[];
      for (var i = 0; i < paths.length; i++) {
        if (!context.mounted) break;
        final p = await procesarFoto(context, paths[i], total: paths.length, done: i);
        if (p != null) pages.add(p);
      }
      return pages.isEmpty ? null : pages;
    }

    final res = await Navigator.of(context).push<LiveScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveScanScreen(limit: limit),
      ),
    );
    if (res == null) return null;

    if (res.useSystemCamera) {
      final imgs = await ScanService.takePhoto();
      if (imgs.isEmpty || !context.mounted) return null;
      final p = await procesarFoto(context, imgs.first);
      return p == null ? null : [p];
    }
    return res.pages.isEmpty ? null : res.pages;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la captura: $e')),
      );
    }
    return null;
  }
}
