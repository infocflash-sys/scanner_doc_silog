import 'package:flutter/material.dart';

import '../screens/live_scan_screen.dart';
import 'scan_service.dart';

/// Flujo común de captura. Devuelve las páginas o `null` si el usuario canceló.
///
/// - Escanear: cámara en vivo con detección de la hoja y disparo automático.
/// - Galería: el usuario elige fotos; la app detecta y recorta la hoja.
Future<CaptureResult?> capturar(
  BuildContext context, {
  required int limit,
  bool galeria = false,
}) async {
  try {
    if (galeria) {
      final imgs = await ScanService.pickFromGallery(limit: limit);
      return imgs.isEmpty ? null : CaptureResult(imgs, autoDetect: true);
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
      return imgs.isEmpty ? null : CaptureResult(imgs, autoDetect: true);
    }
    return res.paths.isEmpty ? null : CaptureResult(res.paths, autoDetect: true);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la captura: $e')),
      );
    }
    return null;
  }
}
