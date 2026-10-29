import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Borra los archivos temporales que genera el flujo de escaneo (fotos de la cámara,
/// imágenes base/procesadas, copias del selector y PDFs) para no acumular espacio.
///
/// Solo limpia temporales; los PDF se arman en el temporal y se suben en el momento.
class TempCleaner {
  static final _images = RegExp(r'^(cap_|base_|pg_|image_picker|scaled_).*\.(jpe?g|png)$', caseSensitive: false);

  static Future<void> clean() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (_images.hasMatch(name) || name.toLowerCase().endsWith('.pdf')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
