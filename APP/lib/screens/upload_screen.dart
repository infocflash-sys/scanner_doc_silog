import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../services/temp_cleaner.dart';
import '../widgets/common.dart';

enum _Stage { generando, subiendo, exito, duplicado, guardadoOffline, error }

class UploadScreen extends StatefulWidget {
  final PiezaInfo info;
  final List<String> paths;
  const UploadScreen({super.key, required this.info, required this.paths});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  _Stage _stage = _Stage.generando;
  double _progress = 0;
  String _msg = '';
  UploadResult? _result;
  File? _pdf;

  bool get _working => _stage == _Stage.generando || _stage == _Stage.subiendo;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _stage = _Stage.generando;
      _progress = 0;
    });
    try {
      _pdf ??= await PdfService.build(widget.info.id, widget.paths);
      if (!mounted) return;
      setState(() => _stage = _Stage.subiendo);

      final r = await ApiService.instance.subirPdf(
        _pdf!,
        widget.info.id,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await StorageService.addHistorial(HistorialItem(
        id: widget.info.id,
        cliente: widget.info.cliente,
        file: r.file,
        paginas: widget.paths.length,
        fecha: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() {
        _result = r;
        _stage = _Stage.exito;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.yaTienePdf) {
        setState(() {
          _msg = e.message;
          _stage = _Stage.duplicado;
        });
      } else if (e.offline) {
        await StorageService.guardarPendiente(_pdf!, widget.info.id);
        if (!mounted) return;
        setState(() {
          _msg = e.message;
          _stage = _Stage.guardadoOffline;
        });
      } else {
        setState(() {
          _msg = e.message;
          _stage = _Stage.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'No se pudo generar el PDF: $e';
        _stage = _Stage.error;
      });
    }
  }

  void _finish() {
    TempCleaner.clean();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        body: GlowBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AnimatedSwitcher(
                  duration: 350.ms,
                  child: KeyedSubtree(key: ValueKey(_stage), child: _content()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (_stage) {
      case _Stage.generando:
      case _Stage.subiendo:
        final gen = _stage == _Stage.generando;
        return AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: gen ? null : _progress,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Brand.border,
                        color: Brand.green,
                      ),
                    ),
                    Icon(gen ? Icons.picture_as_pdf_rounded : Icons.cloud_upload_rounded,
                        size: 42, color: Brand.green),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(gen ? 'Generando PDF…' : 'Subiendo… ${(_progress * 100).round()}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.text)),
              const SizedBox(height: 6),
              Text('${widget.paths.length} página(s) · Pieza #${widget.info.id}',
                  style: const TextStyle(color: Brand.muted)),
            ],
          ),
        );

      case _Stage.exito:
        return _Result(
          icon: Icons.check_circle_rounded,
          color: Brand.green,
          title: '¡Documento subido!',
          body: '${_result!.file}\nPieza #${widget.info.id} · ${widget.info.cliente}\n'
              '${widget.paths.length} página(s)',
          primaryLabel: 'Nuevo escaneo',
          onPrimary: _finish,
        );

      case _Stage.duplicado:
        return _Result(
          icon: Icons.lock_rounded,
          color: Brand.warn,
          title: 'La pieza ya tiene un PDF',
          body: 'Esta pieza ya cuenta con un documento asignado, por lo que no se subió el nuevo '
              'archivo para evitar duplicados o sobrescrituras.\n\n'
              'Si necesitas reemplazarlo, pide a un administrador que elimine el PDF actual del ERP.',
          primaryLabel: 'Entendido',
          onPrimary: _finish,
        );

      case _Stage.guardadoOffline:
        return _Result(
          icon: Icons.cloud_off_rounded,
          color: Brand.warn,
          title: 'Sin conexión',
          body: '$_msg\n\nEl PDF quedó guardado en el dispositivo. Podrás enviarlo desde la pantalla '
              'de inicio cuando vuelva la conexión.',
          primaryLabel: 'Ir al inicio',
          onPrimary: _finish,
        );

      case _Stage.error:
        return _Result(
          icon: Icons.error_rounded,
          color: Brand.danger,
          title: 'No se pudo subir',
          body: _msg,
          primaryLabel: 'Reintentar',
          onPrimary: _run,
          secondaryLabel: 'Volver',
          onSecondary: () => Navigator.pop(context),
        );
    }
  }
}

class _Result extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _Result({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: color.withValues(alpha: 0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 84, color: color)
              .animate()
              .scale(begin: const Offset(0.3, 0.3), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.text)),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.45)),
          const SizedBox(height: 24),
          GradientButton(label: primaryLabel, onPressed: onPrimary),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 10),
            GhostButton(label: secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}
