import 'package:flutter/foundation.dart';

class Bloqueo {
  final String mensaje;
  final String url;
  const Bloqueo(this.mensaje, this.url);
}

/// Si el servidor no habilita esta versión de la app, `bloqueo` deja de ser null y se cubre toda la app.
class AppStatus {
  AppStatus._();
  static final AppStatus instance = AppStatus._();

  final ValueNotifier<Bloqueo?> bloqueo = ValueNotifier(null);

  void bloquear(String mensaje, String url) => bloqueo.value = Bloqueo(mensaje, url);
  void liberar() => bloqueo.value = null;
}
