/// Configuración global de la app.
class AppConfig {
  /// Servidor donde viven los endpoints PHP de SILOG.
  static const String baseUrl = 'https://files.intranetflash.com';

  /// Número de build de esta versión (el de pubspec.yaml tras el «+»). Se envía al servidor, que
  /// lo compara con `build_minimo` de la tabla silog_app_config: si es menor, la app queda bloqueada.
  static const int build = 2;

  /// Versión visible (la de pubspec.yaml antes del «+»).
  static const String version = '1.1.0';
  static String get versionLabel => 'v$version (build $build)';

  static const String estadoPath = '/api/estado.php';
  static const String loginPath = '/api/login.php';
  static const String validarPath = '/api/validar_pieza.php';
  static const String subirPath = '/upload_doc.php';

  /// Lado mayor (px) al que se normaliza cada página antes de armar el PDF.
  static const int maxSide = 2200;

  /// Calidad JPEG de las páginas procesadas.
  static const int jpegQuality = 88;

  /// Peso máximo por página (bytes). Las páginas más pesadas se reducen en resolución/calidad;
  /// las que ya caben no se tocan.
  static const int maxPageBytes = 700 * 1024;

  /// Peso máximo del PDF completo. El servidor admite hasta 50 MB (.user.ini y config.local.php);
  /// 20 MB está probado. Con muchas páginas, cada una recibe una parte (total / n).
  static const int maxPdfMb = 20;
  static const int maxPdfBytes = maxPdfMb * 1024 * 1024;

  /// Máximo de páginas por documento.
  static const int maxPages = 30;
}
