import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';
import '../services/live_detector.dart';

class LiveScanResult {
  final List<String> paths;
  final bool useSystemCamera;
  const LiveScanResult(this.paths, {this.useSystemCamera = false});
}

class _Live {
  final LiveQuad? quad;
  final Nv21Image? img;
  final double stable; // 0..1
  const _Live(this.quad, this.img, this.stable);
}

/// Cámara en vivo: detecta la hoja en tiempo real, la resalta y, cuando está firme y enfocada,
/// dispara sola (opcional). La foto final se toma a resolución completa; el análisis en vivo
/// usa un frame pequeño para ser fluido.
class LiveScanScreen extends StatefulWidget {
  final int limit;
  const LiveScanScreen({super.key, required this.limit});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen> with SingleTickerProviderStateMixin {
  static const _framesToLock = 6; // ≈1 s con 6 fps de análisis

  final _live = ValueNotifier<_Live>(const _Live(null, null, 0));
  final _auto = ValueNotifier<bool>(true);
  final _shots = ValueNotifier<List<String>>([]);
  late final AnimationController _flash;

  String? _tmp;
  CameraState? _cam;
  bool _ready = false;
  bool _showFallback = false;
  bool _capturing = false;
  Timer? _readyTimer;

  List<double>? _prev;
  List<double>? _lastShot;
  int _stable = 0;
  int _misses = 0;
  bool _seenGap = true;
  DateTime _cooldown = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _init();
    _readyTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && !_ready) setState(() => _showFallback = true);
    });
  }

  Future<void> _init() async {
    final dir = await getTemporaryDirectory();
    if (mounted) setState(() => _tmp = dir.path);
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _flash.dispose();
    _live.dispose();
    _auto.dispose();
    _shots.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ───────────── análisis en vivo ─────────────

  Future<void> _onImage(AnalysisImage image) async {
    final nv = image.when(nv21: (i) => i);
    if (nv == null || !mounted) return;

    final rot = switch (nv.rotation) {
      InputAnalysisImageRotation.rotation90deg => 90,
      InputAnalysisImageRotation.rotation180deg => 180,
      InputAnalysisImageRotation.rotation270deg => 270,
      _ => 0,
    };

    final q = LiveDocDetector.detect(nv.bytes, nv.width, nv.height, rot);

    if (q == null) {
      _misses++;
      if (_misses >= 3) {
        _stable = 0;
        _prev = null;
        _seenGap = true;
        _live.value = const _Live(null, null, 0);
      }
      return;
    }
    _misses = 0;

    var delta = 1.0;
    if (_prev != null) {
      delta = 0;
      for (var i = 0; i < 8; i++) {
        delta = math.max(delta, (q.pts[i] - _prev![i]).abs());
      }
    }
    _stable = delta < 0.03 ? _stable + 1 : math.max(0, _stable - 2);
    _prev = q.pts;

    final ratio = (_stable / _framesToLock).clamp(0.0, 1.0);
    _live.value = _Live(q, nv, ratio);

    if (_auto.value &&
        !_capturing &&
        _stable >= _framesToLock &&
        DateTime.now().isAfter(_cooldown) &&
        _isNewPage(q.pts)) {
      _capture();
    }
  }

  /// Evita disparar varias veces sobre la misma hoja: hace falta haberla retirado o movido.
  bool _isNewPage(List<double> pts) {
    if (_lastShot == null || _seenGap) return true;
    var sum = 0.0;
    for (var i = 0; i < 8; i++) {
      sum += (pts[i] - _lastShot![i]).abs();
    }
    return sum / 8 > 0.08;
  }

  // ───────────── captura ─────────────

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _capturing || _tmp == null) return;
    if (_shots.value.length >= widget.limit) {
      _snack('Máximo ${widget.limit} páginas por documento.');
      return;
    }
    _capturing = true;
    HapticFeedback.mediumImpact();
    _flash.forward(from: 0).then((_) => _flash.reverse());
    setState(() {});

    try {
      final photo = cam.when(onPhotoMode: (p) => p) as PhotoCameraState?;
      if (photo == null) throw Exception('La cámara no está lista');
      final req = await photo.takePhoto();
      final path = req.path;
      if (path != null && File(path).existsSync()) {
        _shots.value = [..._shots.value, path];
      } else {
        _snack('No se pudo guardar la foto. Intenta de nuevo.');
      }
    } catch (e) {
      _snack('Error al capturar: $e');
    } finally {
      _capturing = false;
      _cooldown = DateTime.now().add(const Duration(milliseconds: 1800));
      _lastShot = _prev;
      _seenGap = false;
      _stable = 0;
      if (mounted) setState(() {});
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _done() => Navigator.pop(context, LiveScanResult(List.of(_shots.value)));

  Future<void> _close() async {
    if (_shots.value.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Descartar fotos?'),
        content: Text('Tienes ${_shots.value.length} foto(s) tomadas. Si sales, se perderán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_tmp != null)
              Positioned.fill(
                child: CameraAwesomeBuilder.custom(
                  sensorConfig: SensorConfig.single(
                    sensor: Sensor.position(SensorPosition.back),
                    aspectRatio: CameraAspectRatios.ratio_4_3,
                  ),
                  saveConfig: SaveConfig.photo(
                    pathBuilder: (sensors) async => SingleCaptureRequest(
                      '$_tmp/cap_${DateTime.now().millisecondsSinceEpoch}.jpg',
                      sensors.first,
                    ),
                  ),
                  previewFit: CameraPreviewFit.contain,
                  onImageForAnalysis: _onImage,
                  imageAnalysisConfig: AnalysisConfig(
                    maxFramesPerSecond: 6,
                    androidOptions: const AndroidAnalysisOptions.nv21(width: 480),
                  ),
                  progressIndicator: const Center(child: CircularProgressIndicator(color: Brand.green)),
                  builder: (state, preview) {
                    _cam = state;
                    if (!_ready) {
                      _ready = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _showFallback = false);
                      });
                    }
                    return _overlay(state, preview);
                  },
                ),
              ),
            _topBar(),
            _bottomBar(),
            if (_showFallback && !_ready) _fallbackCard(),
            IgnorePointer(
              child: FadeTransition(
                opacity: _flash.drive(Tween(begin: 0.0, end: 0.7)),
                child: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Capa sobre la vista previa: contorno de la hoja, guía y estado.
  Widget _overlay(CameraState state, AnalysisPreview preview) {
    return ValueListenableBuilder<_Live>(
      valueListenable: _live,
      builder: (context, live, _) {
        List<Offset>? pts;
        if (live.quad != null && live.img != null) {
          final q = live.quad!;
          pts = [
            for (var i = 0; i < 4; i++)
              preview.convertFromImage(
                Offset(q.pts[i * 2] * q.uprightW, q.pts[i * 2 + 1] * q.uprightH),
                live.img!,
                flipXY: false,
              ),
          ];
        }
        final locked = live.stable >= 1;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _QuadPainter(pts, locked, preview.rect)),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: Center(child: _statusPill(live)),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 16,
              child: SafeArea(child: _flashButton(state)),
            ),
          ],
        );
      },
    );
  }

  Widget _statusPill(_Live live) {
    String text;
    Color color = Colors.black.withValues(alpha: 0.6);
    if (_capturing) {
      text = 'Capturando…';
    } else if (live.quad == null) {
      text = 'Apunta a la hoja';
    } else if (live.stable < 1) {
      text = 'Mantén firme…';
    } else {
      text = _auto.value ? '¡Listo! Capturando…' : 'Toca el botón para capturar';
      color = Brand.green.withValues(alpha: 0.85);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }

  Widget _flashButton(CameraState state) {
    return StreamBuilder<FlashMode>(
      stream: state.sensorConfig.flashMode$,
      initialData: FlashMode.none,
      builder: (context, snap) {
        final on = snap.data == FlashMode.always;
        return _CircleBtn(
          icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          active: on,
          onTap: () => state.sensorConfig.setFlashMode(on ? FlashMode.none : FlashMode.always),
        );
      },
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            _CircleBtn(icon: Icons.close_rounded, onTap: _close),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: _auto,
              builder: (_, on, _) => GestureDetector(
                onTap: () => _auto.value = !on,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: on ? Brand.green.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(on ? 'Auto' : 'Manual',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 56), // lugar del flash (lo dibuja la capa de la cámara)
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: ValueListenableBuilder<List<String>>(
              valueListenable: _shots,
              builder: (context, shots, _) => Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: shots.isEmpty
                          ? const SizedBox(width: 56)
                          : Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(shots.last),
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    cacheWidth: 160,
                                  ),
                                ),
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Brand.green,
                                    child: Text('${shots.length}',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  _shutter(),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: shots.isEmpty
                          ? const SizedBox(width: 56)
                          : GestureDetector(
                              onTap: _done,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                                child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shutter() {
    return ValueListenableBuilder<_Live>(
      valueListenable: _live,
      builder: (context, live, _) => GestureDetector(
        onTap: _capturing ? null : _capture,
        child: SizedBox(
          width: 82,
          height: 82,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: _auto.value && live.quad != null ? live.stable : 0,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.35),
                  color: Brand.green,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _capturing ? 52 : 62,
                height: _capturing ? 52 : 62,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackCard() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 150,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Brand.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Brand.warn.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '¿La cámara no abre?\nRevisa que la app tenga permiso de cámara, o usa la cámara del sistema.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.text, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, const LiveScanResult([], useSystemCamera: true)),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Usar cámara del sistema'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _CircleBtn({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => Material(
        color: active ? Brand.warn.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      );
}

class _QuadPainter extends CustomPainter {
  final List<Offset>? pts;
  final bool locked;
  final Rect previewRect;
  const _QuadPainter(this.pts, this.locked, this.previewRect);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts == null) {
      // Guía de encuadre mientras no hay hoja
      final w = previewRect.width * 0.78;
      final h = math.min(previewRect.height * 0.8, w * 1.41);
      final r = Rect.fromCenter(center: previewRect.center, width: w, height: h);
      const len = 34.0;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55);
      final path = Path()
        ..moveTo(r.left, r.top + len)
        ..lineTo(r.left, r.top)
        ..lineTo(r.left + len, r.top)
        ..moveTo(r.right - len, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.top + len)
        ..moveTo(r.right, r.bottom - len)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.right - len, r.bottom)
        ..moveTo(r.left + len, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..lineTo(r.left, r.bottom - len);
      canvas.drawPath(path, p);
      return;
    }

    final color = locked ? Brand.green : Brand.warn;
    final quad = Path()..addPolygon(pts!, true);
    canvas.drawPath(quad, Paint()..color = color.withValues(alpha: locked ? 0.26 : 0.16));
    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    for (final p in pts!) {
      canvas.drawCircle(p, 8, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}
