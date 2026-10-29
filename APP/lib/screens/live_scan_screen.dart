import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/capture_flow.dart';

class LiveScanResult {
  final List<ScanPage> pages; // páginas ya recortadas y procesadas
  final bool useSystemCamera;
  const LiveScanResult(this.pages, {this.useSystemCamera = false});
}

/// Cámara con disparador MANUAL (como CamScanner): enfoca y toma la foto al tocar el botón;
/// enseguida se abre la pantalla para ubicar las esquinas con el dedo y la página se procesa
/// con esos límites. Luego se vuelve a la cámara para la siguiente página.
class LiveScanScreen extends StatefulWidget {
  final int limit;
  const LiveScanScreen({super.key, required this.limit});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen> with SingleTickerProviderStateMixin {
  final _pages = ValueNotifier<List<ScanPage>>([]);
  late final AnimationController _flash;

  String? _tmp;
  CameraState? _cam;
  bool _ready = false;
  bool _showFallback = false;
  bool _capturing = false;
  Timer? _readyTimer;

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
    _pages.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ───────────── captura ─────────────

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _capturing || _tmp == null) return;
    if (_pages.value.length >= widget.limit) {
      _snack('Máximo ${widget.limit} páginas por documento.');
      return;
    }
    _capturing = true;
    setState(() {});

    String? path;
    try {
      final photo = cam.when(onPhotoMode: (p) => p) as PhotoCameraState?;
      if (photo == null) throw Exception('La cámara no está lista');
      // Enfoca antes de disparar (como las apps de escaneo) para que el texto salga nítido.
      try {
        photo.focus();
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (_) {}
      HapticFeedback.mediumImpact();
      _flash.forward(from: 0).then((_) => _flash.reverse());
      final req = await photo.takePhoto();
      path = req.path;
      if (path == null || !File(path).existsSync()) {
        path = null;
        _snack('No se pudo guardar la foto. Intenta de nuevo.');
      }
    } catch (e) {
      _snack('Error al capturar: $e');
    }

    // Ubicar esquinas + procesar esa página (pantalla propia); luego se vuelve a la cámara.
    if (path != null && mounted) {
      final page = await procesarFoto(context, path);
      if (page != null && mounted) _pages.value = [..._pages.value, page];
    }

    _capturing = false;
    if (mounted) setState(() {});
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _done() => Navigator.pop(context, LiveScanResult(List.of(_pages.value)));

  Future<void> _close() async {
    if (_pages.value.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Descartar páginas?'),
        content: Text('Tienes ${_pages.value.length} página(s) procesadas. Si sales, se perderán.'),
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

  /// Capa sobre la vista previa: guía de encuadre, indicación y flash. El toque sobre la
  /// imagen enfoca ese punto (lo gestiona la cámara).
  Widget _overlay(CameraState state, AnalysisPreview preview) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(preview.rect))),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    _capturing ? 'Enfocando y capturando…' : 'Encuadra la hoja y toca el disparador',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
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
            child: ValueListenableBuilder<List<ScanPage>>(
              valueListenable: _pages,
              builder: (context, pages, _) => Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: pages.isEmpty
                          ? const SizedBox(width: 56)
                          : Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(pages.last.out),
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
                                    child: Text('${pages.length}',
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
                      child: pages.isEmpty
                          ? const SizedBox(width: 56)
                          : GestureDetector(
                              onTap: _capturing ? null : _done,
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
    return GestureDetector(
      onTap: _capturing ? null : _capture,
      child: SizedBox(
        width: 82,
        height: 82,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 5),
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

/// Guía de encuadre: cuatro esquinas sobre la vista previa.
class _GuidePainter extends CustomPainter {
  final Rect previewRect;
  const _GuidePainter(this.previewRect);

  @override
  void paint(Canvas canvas, Size size) {
    final w = previewRect.width * 0.82;
    final h = math.min(previewRect.height * 0.82, w * 1.41);
    final r = Rect.fromCenter(center: previewRect.center, width: w, height: h);
    const len = 34.0;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.6);
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
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.previewRect != previewRect;
}
