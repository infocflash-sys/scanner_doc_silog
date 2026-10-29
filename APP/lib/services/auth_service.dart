import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Session {
  final String token;
  final int uid;
  final String nombre;
  final DateTime expira; // vencimiento del token (lo fija el servidor: 24 h)
  DateTime ultimo; // última actividad del usuario en la app
  Session({required this.token, required this.uid, required this.nombre, required this.expira, DateTime? ultimo})
      : ultimo = ultimo ?? DateTime.now();

  /// Máxima inactividad tolerada: pasado este tiempo sin usar la app se pide ingresar de nuevo.
  static const inactividad = Duration(hours: 8);

  bool get vigente {
    final ahora = DateTime.now();
    return ahora.isBefore(expira) && ahora.difference(ultimo) < inactividad;
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'uid': uid,
        'nombre': nombre,
        'expira': expira.millisecondsSinceEpoch,
        'ultimo': ultimo.millisecondsSinceEpoch,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: '${j['token']}',
        uid: (j['uid'] as num).toInt(),
        nombre: '${j['nombre']}',
        expira: DateTime.fromMillisecondsSinceEpoch((j['expira'] as num).toInt()),
        ultimo: j['ultimo'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['ultimo'] as num).toInt()),
      );
}

/// Sesión del usuario: el token dura 24 h (lo emite el servidor) y además se cierra tras 8 h sin usar
/// la app. Se guarda en disco, así sobrevive a minimizar o a que Android cierre el proceso.
/// Solo se guarda el token y el nombre de usuario, nunca la clave.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// `null` = no hay sesión: la app muestra el login.
  final ValueNotifier<Session?> session = ValueNotifier(null);
  Timer? _timer;

  Session? get actual {
    final s = session.value;
    return (s != null && s.vigente) ? s : null;
  }

  Future<File> _file(String nombre) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/data');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$nombre');
  }

  /// Último usuario que ingresó (solo el nombre, para no tener que escribirlo de nuevo).
  String ultimoUsuario = '';
  DateTime _guardado = DateTime.fromMillisecondsSinceEpoch(0);

  /// Recupera la sesión guardada si todavía es válida.
  Future<void> cargar() async {
    try {
      final u = await _file('usuario.txt');
      if (await u.exists()) ultimoUsuario = (await u.readAsString()).trim();
    } catch (_) {}
    try {
      final f = await _file('sesion.json');
      if (!await f.exists()) return;
      final s = Session.fromJson(Map<String, dynamic>.from(jsonDecode(await f.readAsString())));
      if (s.vigente) {
        _activar(s);
      } else {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<void> iniciar(Session s, {String? usuario}) async {
    if (usuario != null && usuario.isNotEmpty) {
      ultimoUsuario = usuario;
      try {
        await (await _file('usuario.txt')).writeAsString(usuario, flush: true);
      } catch (_) {}
    }
    await _guardar(s);
    _activar(s);
  }

  Future<void> _guardar(Session s) async {
    _guardado = DateTime.now();
    try {
      await (await _file('sesion.json')).writeAsString(jsonEncode(s.toJson()), flush: true);
    } catch (_) {}
  }

  void _activar(Session s) {
    _timer?.cancel();
    // Revisa cada minuto si venció por tiempo o por inactividad.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final a = session.value;
      if (a != null && !a.vigente) cerrar();
    });
    session.value = s;
  }

  /// Registra actividad (cada petición al servidor y al volver a la app): renueva la ventana de
  /// 8 h de inactividad. Se escribe a disco como máximo una vez por minuto.
  void tocar() {
    final s = session.value;
    if (s == null || !s.vigente) return;
    s.ultimo = DateTime.now();
    if (DateTime.now().difference(_guardado) > const Duration(minutes: 1)) _guardar(s);
  }

  /// Al volver a la app (tras minimizarla): si venció se cierra; si no, cuenta como actividad.
  /// Si por algún motivo no hay sesión en memoria, intenta recuperarla del disco.
  Future<void> alVolver() async {
    final s = session.value;
    if (s == null) {
      await cargar();
    } else if (!s.vigente) {
      await cerrar();
    } else {
      tocar();
    }
  }

  Future<void> cerrar() async {
    _timer?.cancel();
    session.value = null;
    try {
      final f = await _file('sesion.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
