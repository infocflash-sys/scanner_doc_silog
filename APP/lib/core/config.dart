/// Configuración global de la app.
class AppConfig {
  /// Servidor donde viven los endpoints PHP de SILOG.
  static const String baseUrl = 'https://files.intranetflash.com';

  static const String validarPath = '/api/validar_pieza.php';
  static const String subirPath = '/upload_doc.php';

  /// Lado mayor (px) al que se normaliza cada página antes de armar el PDF.
  static const int maxSide = 2200;

  /// Calidad JPEG de las páginas procesadas.
  static const int jpegQuality = 88;

  /// Máximo de páginas por documento.
  static const int maxPages = 30;
}
