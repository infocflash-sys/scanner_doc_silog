import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  /// Arma un PDF A4 con una página por imagen (orientación según la imagen).
  static Future<File> build(String idPieza, List<String> paths) async {
    final doc = pw.Document(
      compress: true,
      title: 'Documentación pieza $idPieza',
      author: 'SILOG',
      creator: 'Doc SILOG',
    );

    for (final p in paths) {
      final bytes = await File(p).readAsBytes();
      final size = await _size(bytes);
      final landscape = size.width > size.height;
      final image = pw.MemoryImage(bytes);

      doc.addPage(
        pw.Page(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$idPieza.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static Future<ui.Size> _size(Uint8List bytes) async {
    final data = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(data);
    final s = ui.Size(desc.width.toDouble(), desc.height.toDouble());
    desc.dispose();
    data.dispose();
    return s;
  }
}
