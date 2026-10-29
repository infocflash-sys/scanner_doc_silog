import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/config.dart';
import '../models/models.dart';
import 'app_status.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  final bool offline;
  final int? retryAfter; // segundos de bloqueo del login
  const ApiException(this.message, {this.code, this.offline = false, this.retryAfter});

  bool get yaTienePdf => code == 'ya_tiene_pdf';
  bool get sesion => code == 'sesion'; // sesión vencida o inválida: hay que volver a ingresar
  bool get bloqueado => code == 'bloqueado';

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      // 10 min: subidas de varios MB con poca señal en terreno.
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 10),
      validateStatus: (s) => s != null && s < 500,
    ),
  )..interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        o.headers['X-Silog-Build'] = '${AppConfig.build}';
        AuthService.instance.tocar();
        final s = AuthService.instance.actual;
        if (s != null) o.headers['X-Silog-Token'] = s.token;
        h.next(o);
      },
      onResponse: (r, h) {
        // El servidor dice que la sesión ya no vale: se cierra y la app vuelve al login.
        final d = r.data;
        if (r.statusCode == 401 && d is Map && d['code'] == 'sesion') AuthService.instance.cerrar();
        if (r.statusCode == 426 && d is Map && d['code'] == 'version') {
          AppStatus.instance.bloquear('${d['message']}', '${d['url'] ?? ''}');
        }
        h.next(r);
      },
    ));

  /// Consulta si esta versión sigue habilitada. Sin red no bloquea: el servidor igual lo exige en cada petición.
  Future<void> verificarEstado() async {
    try {
      final r = await _dio.get(
        AppConfig.estadoPath,
        options: Options(sendTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)),
      );
      final j = _json(r);
      if (j['permitido'] == false) {
        AppStatus.instance.bloquear('${j['mensaje']}', '${j['url'] ?? ''}');
      } else {
        AppStatus.instance.liberar();
      }
    } catch (_) {}
  }

  Future<Session> login(String usuario, String clave) async {
    try {
      final r = await _dio.post(
        AppConfig.loginPath,
        data: {'username': usuario, 'password': clave},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final j = _json(r);
      if (j['status'] != 'success') {
        throw ApiException(
          '${j['message'] ?? 'No se pudo iniciar sesión'}',
          code: j['code'] as String?,
          retryAfter: (j['retry_after'] as num?)?.toInt(),
        );
      }
      final u = Map<String, dynamic>.from(j['user']);
      return Session(
        token: '${j['token']}',
        uid: (u['id'] as num).toInt(),
        nombre: '${u['nombre']}',
        expira: DateTime.now().add(Duration(seconds: (j['expires_in'] as num).toInt())),
      );
    } on DioException catch (e) {
      throw _net(e);
    }
  }

  Map<String, dynamic> _json(Response r) {
    final d = r.data;
    if (d is Map<String, dynamic>) return d;
    if (d is String) {
      try {
        final m = jsonDecode(d);
        if (m is Map<String, dynamic>) return m;
      } catch (_) {}
    }
    throw const ApiException('Respuesta inesperada del servidor');
  }

  ApiException _net(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException('El servidor tardó demasiado en responder.', offline: true);
      case DioExceptionType.connectionError:
        return const ApiException('Sin conexión a internet.', offline: true);
      default:
        final d = e.response?.data;
        if (d is Map && d['message'] != null) {
          return ApiException('${d['message']}', code: d['code'] as String?);
        }
        return ApiException('El servidor respondió con un error (${e.response?.statusCode ?? '?'}).');
    }
  }

  Future<PiezaInfo> validarPieza(String id) async {
    try {
      final r = await _dio.get(AppConfig.validarPath, queryParameters: {'id_pieza': id});
      final j = _json(r);
      if (j['status'] != 'success') {
        throw ApiException('${j['message'] ?? 'Pieza no encontrada'}', code: j['code'] as String?);
      }
      return PiezaInfo.fromJson(Map<String, dynamic>.from(j['data']));
    } on DioException catch (e) {
      throw _net(e);
    }
  }

  Future<UploadResult> subirPdf(
    File pdf,
    String idPieza, {
    void Function(double)? onProgress,
  }) async {
    try {
      final form = FormData.fromMap({
        'id_pieza': idPieza,
        'pdf_file': await MultipartFile.fromFile(pdf.path, filename: '$idPieza.pdf'),
      });
      final r = await _dio.post(
        AppConfig.subirPath,
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      final j = _json(r);
      if (j['status'] != 'success') {
        throw ApiException('${j['message'] ?? 'Error al subir'}', code: j['code'] as String?);
      }
      return UploadResult('${j['file']}', (j['version'] ?? 1) as int);
    } on DioException catch (e) {
      throw _net(e);
    }
  }
}
