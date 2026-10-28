enum DocFilter {
  original('Original'),
  documento('Documento'),
  gris('Gris'),
  color('Color+');

  final String label;
  const DocFilter(this.label);
}

class PiezaInfo {
  final String id;
  final String cliente;
  final String fecha;
  final bool tienePdf;
  final String? docFile;

  const PiezaInfo({
    required this.id,
    required this.cliente,
    required this.fecha,
    required this.tienePdf,
    this.docFile,
  });

  factory PiezaInfo.fromJson(Map<String, dynamic> j) => PiezaInfo(
        id: '${j['id']}',
        cliente: '${j['cliente'] ?? '-'}',
        fecha: '${j['fecha_creacion'] ?? ''}',
        tienePdf: j['tiene_pdf'] == true,
        docFile: (j['docum_file'] == null || '${j['docum_file']}'.isEmpty)
            ? null
            : '${j['docum_file']}',
      );
}

class UploadResult {
  final String file;
  final int version;
  const UploadResult(this.file, this.version);
}

/// Una página del documento en edición.
class ScanPage {
  final int id;
  final String src; // imagen tal como llegó (escáner, cámara o galería)
  final bool autoDetect; // detectar la hoja automáticamente (no hace falta si ya vino recortada)
  int bw = 0, bh = 0; // tamaño de la imagen base
  String base; // imagen orientada y acotada, sobre la que se recorta
  String out; // imagen procesada (la que va al PDF)
  DocFilter filter;
  int turns; // giros de 90° en sentido horario
  List<double>? corners; // esquinas normalizadas TL,TR,BR,BL; null = hoja completa
  bool busy;

  ScanPage({
    required this.id,
    required this.src,
    required this.autoDetect,
    this.filter = DocFilter.documento,
    this.turns = 0,
    this.corners,
    this.busy = false,
  })  : base = src,
        out = src;
}

class HistorialItem {
  final String id;
  final String cliente;
  final String file;
  final int paginas;
  final DateTime fecha;

  const HistorialItem({
    required this.id,
    required this.cliente,
    required this.file,
    required this.paginas,
    required this.fecha,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'cliente': cliente,
        'file': file,
        'paginas': paginas,
        'fecha': fecha.toIso8601String(),
      };

  factory HistorialItem.fromJson(Map<String, dynamic> j) => HistorialItem(
        id: '${j['id']}',
        cliente: '${j['cliente']}',
        file: '${j['file']}',
        paginas: (j['paginas'] ?? 0) as int,
        fecha: DateTime.tryParse('${j['fecha']}') ?? DateTime.now(),
      );
}
