import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/image_service.dart';
import '../widgets/common.dart';

/// Resultado del editor. `corners == null` significa "hoja completa, sin recorte".
class CropResult {
  final List<double>? corners;
  const CropResult(this.corners);
}

/// Editor de recorte: 4 esquinas arrastrables sobre la imagen base (TL, TR, BR, BL).
class CropScreen extends StatefulWidget {
  final String basePath;
  final int width;
  final int height;
  final List<double>? initial;
  const CropScreen({
    super.key,
    required this.basePath,
    required this.width,
    required this.height,
    this.initial,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  static const _full = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];

  late List<Offset> _pts;
  int? _active;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _pts = _toPts(widget.initial ?? _inset());
  }

  List<double> _inset() => const [0.08, 0.08, 0.92, 0.08, 0.92, 0.92, 0.08, 0.92];

  List<Offset> _toPts(List<double> c) => [for (var i = 0; i < 4; i++) Offset(c[i * 2], c[i * 2 + 1])];

  List<double> _toList() => [for (final p in _pts) ...[p.dx, p.dy]];

  Future<void> _auto() async {
    setState(() => _detecting = true);
    final c = await ImageService.detectar(widget.basePath);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      if (c != null) _pts = _toPts(c);
    });
    if (c == null) {
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

  void _apply() {
    if (!_convexAndBig()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las esquinas se cruzan o el área es muy pequeña.')),
      );
      return;
    }
    Navigator.pop(context, CropResult(_isFull ? null : _toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar recorte'), backgroundColor: Brand.bg),
      body: GlowBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Arrastra las esquinas hasta los bordes de la hoja',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.muted),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    const pad = 24.0;
                    final avail = Size(box.maxWidth - pad * 2, box.maxHeight - pad * 2);
                    final scale = (avail.width / widget.width).clamp(0.0, avail.height / widget.height);
                    final size = Size(widget.width * scale, widget.height * scale);
                    final origin = Offset((box.maxWidth - size.width) / 2, (box.maxHeight - size.height) / 2);

                    Offset toScreen(Offset n) => origin + Offset(n.dx * size.width, n.dy * size.height);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        int? best;
                        var bestD = 70.0;
                        for (var i = 0; i < 4; i++) {
                          final dist = (toScreen(_pts[i]) - d.localPosition).distance;
                          if (dist < bestD) {
                            bestD = dist;
                            best = i;
                          }
                        }
                        setState(() => _active = best);
                      },
                      onPanUpdate: (d) {
                        final i = _active;
                        if (i == null) return;
                        final n = Offset(
                          ((d.localPosition.dx - origin.dx) / size.width).clamp(0.0, 1.0),
                          ((d.localPosition.dy - origin.dy) / size.height).clamp(0.0, 1.0),
                        );
                        setState(() => _pts[i] = n);
                      },
                      onPanEnd: (_) => setState(() => _active = null),
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
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GhostButton(
                            label: 'Auto',
                            icon: Icons.auto_fix_high_rounded,
                            onPressed: _detecting ? null : _auto,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GhostButton(
                            label: 'Hoja completa',
                            icon: Icons.crop_free_rounded,
                            onPressed: () => setState(() => _pts = _toPts(_full)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GradientButton(label: 'Aplicar recorte', icon: Icons.check_rounded, onPressed: _apply),
                  ],
                ),
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
      final r = i == active ? 20.0 : 15.0;
      canvas.drawCircle(pts[i], r + 4, Paint()..color = Brand.green.withValues(alpha: 0.28));
      canvas.drawCircle(pts[i], r, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], r - 4, Paint()..color = Brand.green);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
