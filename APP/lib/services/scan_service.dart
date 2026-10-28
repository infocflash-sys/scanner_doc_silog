import 'package:image_picker/image_picker.dart';

/// Páginas capturadas. La app siempre detecta y recorta la hoja por su cuenta.
class CaptureResult {
  final List<String> paths;
  final bool autoDetect;
  const CaptureResult(this.paths, {required this.autoDetect});
}

class ScanService {
  /// Cámara del sistema (una foto). Alternativa si la cámara en vivo no está disponible.
  static Future<List<String>> takePhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, requestFullMetadata: false);
    return f == null ? const [] : [f.path];
  }

  /// Selector de fotos del sistema (permite elegir varias).
  static Future<List<String>> pickFromGallery({required int limit}) async {
    final files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    return files.take(limit).map((f) => f.path).toList();
  }
}
