import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  final bool offline;
  const ApiException(this.message, {this.code, this.offline = false});

  bool get yaTienePdf => code == 'ya_tiene_pdf';

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
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 120),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

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
