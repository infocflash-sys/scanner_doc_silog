import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/image_service.dart';
import '../services/capture_flow.dart';
import '../widgets/common.dart';
import '../widgets/segment_ring.dart';
import 'crop_screen.dart';
import 'upload_screen.dart';

class ReviewScreen extends StatefulWidget {
  final PiezaInfo info;
  final List<ScanPage> initialPages;
  const ReviewScreen({
    super.key,
    required this.info,
    required this.initialPages,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final List<ScanPage> _pages = [];
  int? _selId;
  String _tmp = '';
  bool _adding = false;

  ScanPage? get _sel {
    for (final p in _pages) {
      if (p.id == _selId) return p;
    }
    return null;
  }

  bool get _anyBusy => _pages.any((p) => p.busy);

  // Aro de progreso de los reprocesos (filtro, giro o recorte): una barrita por tarea.
  int _bTotal = 0;
  int _bDone = 0;

  void _taskEnd() {
    if (!mounted) return;
    setState(() => _bDone++);
    if (_bDone >= _bTotal) {
      // Deja ver el aro completo un instante y lo oculta.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _bDone >= _bTotal) {
          setState(() {
            _bTotal = 0;
            _bDone = 0;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Las páginas llegan ya recortadas y procesadas: la galería no tiene cola de procesamiento.
    _pages.addAll(widget.initialPages);
    _selId = _pages.isNotEmpty ? _pages.first.id : null;
    getTemporaryDirectory().then((d) => _tmp = d.path);
  }

  Future<void> _reprocess(ScanPage p, {bool track = true}) async {
    setState(() {
      p.busy = true;
      if (track) _bTotal++;
    });
    try {
      final dst = '$_tmp/pg_${p.id}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final old = p.out;
      p.out = await ImageService.procesar(
        basePath: p.base,
        dst: dst,
        filter: p.filter,
        turns: p.turns,
        corners: p.corners,
      );
      if (old != p.src && old != p.out && old.startsWith(_tmp)) {
        try {
          File(old).deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo procesar una página.')),
        );
      }
    } finally {
      if (mounted) setState(() => p.busy = false);
      if (track) _taskEnd();
    }
  }

  void _setFilter(DocFilter f) {
    final p = _sel;
    if (p == null || p.filter == f) return;
    p.filter = f;
    _reprocess(p);
  }

  void _rotate() {
    final p = _sel;
    if (p == null) return;
    p.turns = (p.turns + 1) % 4;
    _reprocess(p);
  }

  Future<void> _crop() async {
    final p = _sel;
    if (p == null || p.busy || p.bw == 0) return;
    final r = await Navigator.push<CropResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CropScreen(
          basePath: p.base,
          width: p.bw,
          height: p.bh,
          initial: p.corners,
        ),
      ),
    );
    if (r == null || !mounted) return;
    p.corners = r.corners;
    _reprocess(p);
  }

  Future<void> _delete() async {
    final p = _sel;
    if (p == null) return;
    if (_pages.length == 1) {
      Navigator.pop(context);
      return;
    }
    final i = _pages.indexOf(p);
    setState(() {
      _pages.removeAt(i);
      _selId = _pages[i.clamp(0, _pages.length - 1)].id;
    });
  }

  Future<void> _addMore({required bool galeria}) async {
    final left = AppConfig.maxPages - _pages.length;
    if (left <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Máximo ${AppConfig.maxPages} páginas por documento.')),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      final res = await capturar(context, limit: left, galeria: galeria);
      if (res != null && res.isNotEmpty && mounted) {
        setState(() {
          _pages.addAll(res);
          _selId = res.first.id;
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: Brand.border, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 18),
              _MenuTile(
                icon: Icons.document_scanner_rounded,
                title: 'Escanear con cámara',
                subtitle: 'Tomas la foto y marcas las esquinas',
                onTap: () {
                  Navigator.pop(context);
                  _addMore(galeria: false);
                },
              ),
              const SizedBox(height: 10),
              _MenuTile(
                icon: Icons.photo_library_rounded,
                title: 'Elegir de la galería',
                subtitle: 'Opcional: usa fotos ya tomadas',
                onTap: () {
                  Navigator.pop(context);
                  _addMore(galeria: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    return Scaffold(
      appBar: AppBar(
        title: Text('Revisar · ${_pages.length} pág.'),
        backgroundColor: Brand.bg,
      ),
      body: GlowBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (_bTotal > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Brand.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Brand.border),
                  ),
                  child: Row(
                    children: [
                      SegmentRing(total: _bTotal, done: _bDone),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _bDone >= _bTotal ? 'Listo' : 'Procesando páginas…',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.text),
                            ),
                            Text(
                              '${_bDone.clamp(0, _bTotal)} de $_bTotal',
                              style: const TextStyle(color: Brand.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Vista previa con zoom para comprobar legibilidad
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Brand.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: sel == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: Image.file(
                                File(sel.out),
                                key: ValueKey(sel.out),
                                fit: BoxFit.contain,
                              ),
                            ),
                            if (sel.busy)
                              Container(
                                color: Colors.black54,
                                child: const Center(child: CircularProgressIndicator(color: Brand.green)),
                              ),
                            Positioned(
                              top: 12,
                              left: 12,
                              child: _Pill('Página ${_pages.indexOf(sel) + 1}'),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  _RoundBtn(Icons.crop_rounded, _crop),
                                  const SizedBox(width: 8),
                                  _RoundBtn(Icons.rotate_right_rounded, _rotate),
                                  const SizedBox(width: 8),
                                  _RoundBtn(Icons.delete_outline_rounded, _delete, danger: true),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              // Filtros
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final f in DocFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: sel?.filter == f,
                          onSelected: (_) => _setFilter(f),
                          selectedColor: Brand.green.withValues(alpha: 0.25),
                          backgroundColor: Brand.surface2,
                          side: BorderSide(color: sel?.filter == f ? Brand.green : Brand.border),
                          labelStyle: TextStyle(
                            color: sel?.filter == f ? Brand.green : Brand.text,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Miniaturas reordenables (mantén presionado para arrastrar)
              SizedBox(
                height: 92,
                child: Row(
                  children: [
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 16),
                        buildDefaultDragHandles: true,
                        itemCount: _pages.length,
                        onReorderItem: (o, n) {
                          setState(() => _pages.insert(n, _pages.removeAt(o)));
                        },
                        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                        itemBuilder: (_, i) {
                          final p = _pages[i];
                          final active = p.id == _selId;
                          return GestureDetector(
                            key: ValueKey(p.id),
                            onTap: () => setState(() => _selId = p.id),
                            child: Container(
                              width: 68,
                              margin: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: active ? Brand.green : Brand.border,
                                  width: active ? 2.5 : 1,
                                ),
                                color: Colors.white,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(p.out),
                                    fit: BoxFit.cover,
                                    cacheWidth: 200,
                                    key: ValueKey('t${p.out}'),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 4,
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        shadows: [Shadow(blurRadius: 4)],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16, left: 4),
                      child: InkWell(
                        onTap: _adding ? null : _showAddMenu,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 62,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Brand.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Brand.green.withValues(alpha: 0.6)),
                          ),
                          child: _adding
                              ? const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5),
                                  ),
                                )
                              : const Icon(Icons.add_a_photo_rounded, color: Brand.green),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Límite de subida: ${AppConfig.maxPdfMb} MB por documento. Si lo supera, se reducirá '
                        'la calidad o tendrás que quitar páginas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Brand.muted.withValues(alpha: 0.9)),
                      ),
                    ),
                    GradientButton(
                  label: 'Generar y subir PDF',
                  icon: Icons.cloud_upload_rounded,
                  onPressed: (_pages.isEmpty || _anyBusy)
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UploadScreen(
                                info: widget.info,
                                paths: _pages.map((p) => p.out).toList(),
                              ),
                            ),
                          ),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _RoundBtn(this.icon, this.onTap, {this.danger = false});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: danger ? Brand.danger : Colors.white),
          ),
        ),
      );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Brand.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Brand.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: Brand.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.text)),
                    Text(subtitle, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Brand.muted),
            ],
          ),
        ),
      );
}
