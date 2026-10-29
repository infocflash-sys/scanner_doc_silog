import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Historial reciente de documentos subidos.
class StorageService {
  static Future<Directory> _dir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ---------- Historial ----------
  static Future<File> _histFile() async {
    final d = await _dir('data');
    return File('${d.path}/historial.json');
  }

  static Future<List<HistorialItem>> historial() async {
    try {
      final f = await _histFile();
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => HistorialItem.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addHistorial(HistorialItem item) async {
    final items = await historial();
    items.insert(0, item);
    final f = await _histFile();
    await f.writeAsString(jsonEncode(items.take(20).map((e) => e.toJson()).toList()));
  }
}
