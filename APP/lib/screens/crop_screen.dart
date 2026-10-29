import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/image_service.dart';
import '../widgets/common.dart';
import '../widgets/segment_ring.dart';

/// Resultado del editor. `corners == null` significa "hoja completa, sin recorte".
/// `retake` = el usuario pidió volver a tomar la foto. `outPath` = página ya procesada
/// (solo cuando se pasó un `processor`).
class CropResult {
  final List<double>? corners;
  final bool retake;
  final String? outPath;
  const CropResult(this.corners, {this.retake = false, this.outPath});
}

/// Editor de recorte: 4 esquinas arrastrables con el dedo (con lupa) sobre la imagen base
/// (TL, TR, BR, BL). Si recibe un [processor], al confirmar procesa la página con exactamente
/// esas esquinas (mostrando el aro de progreso) y devuelve la ruta de la imagen final.
class CropScreen extends StatefulWidget {
  final String basePath;
  final int width;
  final int height;
  final List<double>? initial;
  final String title;
  final String confirmLabel;
  final bool allowRetake;
  final bool autoOnOpen; // propone las esquinas detectadas al abrir (se pueden mover)
  final Future<String> Function(List<double>? corners)? processor;
  final int batchTotal; // páginas del lote (para el aro de progreso)
  final int batchDone;
  const CropScreen({
    super.key,
    required this.basePath,
    required this.width,
    required this.height,
    this.initial,
    this.title = 'Ajustar recorte',
    this.confirmLabel = 'Aplicar recorte',
    this.allowRetake = false,
    this.autoOnOpen = false,
    this.processor,
    this.batchTotal = 1,
    this.batchDone = 0,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  static const _full = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
  static const _hit = 90.0; // radio táctil de cada esquina (px)
  static const _loupe = 124.0;

  late List<Offset> _pts;
  int? _active;
  int? _ptr;
  Offset _last = Offset.zero;
  bool _detecting = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _pts = _toPts(widget.initial ?? _inset());
    if (widget.initial == null && widget.autoOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _auto(silent: true));
    }
  }

  List<double> _inset() => const [0.06, 0.06, 0.94, 0.06, 0.94, 0.94, 0.06, 0.94];

  List<Offset> _toPts(List<double> c) => [for (var i = 0; i < 4; i++) Offset(c[i * 2], c[i * 2 + 1])];

  List<double> _toList() => [for (final p in _pts) ...[p.dx, p.dy]];

  Future<void> _auto({bool silent = false}) async {
    setState(() => _detecting = true);
    List<double>? c;
    try {
      c = await ImageService.detectar(widget.basePath);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _detecting = false;
      if (c != null) _pts = _toPts(c);
    });
    if (c == null && !silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se detectó la hoja. Ajusta las esquinas a mano.')),
      );
    }
  }

  bool _convexAndBig() {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = _pts[i], b = _pts[(i + 1) % 4], c = _pts[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    var area = 0.0;
    for (var i = 0; i < 4; i++) {
      final p = _pts[i], q = _pts[(i + 1) % 4];
      area += p.dx * q.dy - q.dx * p.dy;
    }
    return area.abs() / 2 > 0.04;
  }

  bool get _isFull {
    final l = _toList();
    for (var i = 0; i < 8; i++) {
      if ((l[i] - _full[i]).abs() > 0.003) return false;
    }
    return true;
  }

  Future<void> _apply() async {
    if (!_convexAndBig()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las esquinas se cruzan o el área es muy pequeña.')),
      );
      return;
    }
    final corners = _isFull ? null : _toList();
    final proc = widget.processor;
    if (proc == null) {
      Navigator.pop(context, CropResult(corners));
      return;
    }
    setState(() => _processing = true);
    try {
      final out = await proc(corners);
      if (mounted) Navigator.pop(context, CropResult(corners, outPath: out));
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo procesar la página. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Brand.bg,
          automaticallyImplyLeading: !_processing,
        ),
        body: GlowBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Arrastra cada punto hasta una esquina de la hoja',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Brand.muted),
                      ),
                    ),
                    Expanded(child: _editor()),
                    _actions(),
                  ],
                ),
                if (_processing) _procesando(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 24.0;
        final avail = Size(box.maxWidth - pad * 2, box.maxHeight - pad * 2);
        final scale = (avail.width / widget.width).clamp(0.0, avail.height / widget.height);
        final size = Size(widget.width * scale, widget.height * scale);
        final origin = Offset((box.maxWidth - size.width) / 2, (box.maxHeight - size.height) / 2);

        Offset toScreen(Offset n) => origin + Offset(n.dx * size.width, n.dy * size.height);

        Offset? loupeAt;
        if (_active != null) {
          final c = toScreen(_pts[_active!]);
          loupeAt = Offset(
            box.maxWidth / 2,
            c.dy > box.maxHeight * 0.4 ? _loupe / 2 + 8 : box.maxHeight - _loupe / 2 - 8,
          );
        }

        // Listener (y no GestureDetector): responde al primer toque, sin esperar a que se
        // resuelva el gesto, y el punto se mueve con el desplazamiento del dedo (no salta).
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_ptr != null || _processing) return;
            int? best;
            var bestD = _hit;
            for (var i = 0; i < 4; i++) {
              final dist = (toScreen(_pts[i]) - e.localPosition).distance;
              if (dist < bestD) {
                bestD = dist;
                best = i;
              }
            }
            if (best == null) return;
            _ptr = e.pointer;
            _last = e.localPosition;
            setState(() => _active = best);
          },
          onPointerMove: (e) {
            final i = _active;
            if (i == null || e.pointer != _ptr) return;
            final d = e.localPosition - _last;
            _last = e.localPosition;
            setState(() {
              _pts[i] = Offset(
                (_pts[i].dx + d.dx / size.width).clamp(0.0, 1.0),
                (_pts[i].dy + d.dy / size.height).clamp(0.0, 1.0),
              );
            });
          },
          onPointerUp: (e) {
            if (e.pointer != _ptr) return;
            _ptr = null;
            setState(() => _active = null);
          },
          onPointerCancel: (e) {
            if (e.pointer != _ptr) return;
            _ptr = null;
            setState(() => _active = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: origin.dx,
                top: origin.dy,
                width: size.width,
                height: size.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(widget.basePath), fit: BoxFit.fill),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropPainter(
                    pts: [for (final p in _pts) toScreen(p)],
                    imageRect: origin & size,
                    active: _active,
                  ),
                ),
              ),
              if (_detecting)
                Positioned.fromRect(
                  rect: origin & size,
                  child: Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator(color: Brand.green)),
                  ),
                ),
              if (loupeAt != null) ...[
                Positioned(
                  left: loupeAt.dx - _loupe / 2,
                  top: loupeAt.dy - _loupe / 2,
                  child: IgnorePointer(
                    child: RawMagnifier(
                      size: const Size(_loupe, _loupe),
                      magnificationScale: 2.4,
                      focalPointOffset: toScreen(_pts[_active!]) - loupeAt,
                      decoration: const MagnifierDecoration(
                        shape: CircleBorder(side: BorderSide(color: Brand.green, width: 3)),
                        shadows: [BoxShadow(color: Colors.black54, blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: loupeAt.dx - 10,
                  top: loupeAt.dy - 10,
                  child: const IgnorePointer(child: Icon(Icons.add_rounded, size: 20, color: Brand.warn)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.allowRetake) ...[
                Expanded(
                  child: GhostButton(
                    label: 'Volver a tomar',
                    icon: Icons.replay_rounded,
                    onPressed: _processing
                        ? null
                        : () => Navigator.pop(context, const CropResult(null, retake: true)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GhostButton(
                  label: 'Auto',
                  icon: Icons.auto_fix_high_rounded,
                  onPressed: (_detecting || _processing) ? null : _auto,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Completa',
                  icon: Icons.crop_free_rounded,
                  onPressed: _processing ? null : () => setState(() => _pts = _toPts(_full)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: widget.confirmLabel,
            icon: Icons.check_rounded,
            onPressed: _processing ? null : _apply,
          ),
        ],
      ),
    );
  }

  Widget _procesando() {
    final total = widget.batchTotal < 1 ? 1 : widget.batchTotal;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentRing(total: total, done: widget.batchDone, size: 96),
              const SizedBox(height: 18),
              const Text('Procesando página…',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.text)),
              const SizedBox(height: 4),
              Text(
                total > 1 ? 'Página ${widget.batchDone + 1} de $total' : 'Recortando y mejorando la imagen',
                style: const TextStyle(color: Brand.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final List<Offset> pts;
  final Rect imageRect;
  final int? active;
  const _CropPainter({required this.pts, required this.imageRect, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()..addPolygon(pts, true);

    // Atenúa lo que queda fuera del recorte
    final outside = Path.combine(PathOperation.difference, Path()..addRect(imageRect), quad);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = Brand.green,
    );

    for (var i = 0; i < 4; i++) {
      final r = i == active ? 24.0 : 19.0;
      canvas.drawCircle(pts[i], r + 5, Paint()..color = Brand.green.withValues(alpha: 0.28));
      canvas.drawCircle(pts[i], r, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], r - 5, Paint()..color = Brand.green);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
