import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/capture_flow.dart';
import '../widgets/common.dart';
import 'review_screen.dart';

class PiezaScreen extends StatefulWidget {
  final PiezaInfo info;
  const PiezaScreen({super.key, required this.info});

  @override
  State<PiezaScreen> createState() => _PiezaScreenState();
}

class _PiezaScreenState extends State<PiezaScreen> {
  bool _scanning = false;

  Future<void> _escanear({bool galeria = false}) async {
    setState(() => _scanning = true);
    try {
      final res = await capturar(context, limit: AppConfig.maxPages, galeria: galeria);
      if (!mounted || res == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            info: widget.info,
            initialPaths: res.paths,
            autoDetect: res.autoDetect,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Pieza')),
      body: GlowBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: Brand.gradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pieza validada', style: TextStyle(color: Brand.muted)),
                              Text('#${info.id}',
                                  style: const TextStyle(
                                      fontSize: 26, fontWeight: FontWeight.w800, color: Brand.text)),
                            ],
                          ),
                        ),
                        Icon(
                          info.tienePdf ? Icons.lock_rounded : Icons.verified_rounded,
                          color: info.tienePdf ? Brand.warn : Brand.green,
                          size: 30,
                        ),
                      ],
                    ),
                    const Divider(height: 28, color: Brand.border),
                    InfoRow(icon: Icons.business_rounded, label: 'Cliente', value: info.cliente),
                    InfoRow(icon: Icons.event_rounded, label: 'Creada', value: info.fecha),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15),
              const SizedBox(height: 20),
              if (info.tienePdf)
                _YaTienePdf(file: info.docFile).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15)
              else ...[
                const AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Para mejores resultados',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Brand.text, fontSize: 16)),
                      SizedBox(height: 10),
                      _Tip(Icons.light_mode_rounded, 'Busca buena luz y evita sombras sobre la hoja.'),
                      _Tip(Icons.crop_free_rounded, 'El escáner detecta los bordes y endereza solo.'),
                      _Tip(Icons.layers_rounded, 'Puedes escanear varias páginas en un solo PDF.'),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms),
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Escanear documento',
                  icon: Icons.document_scanner_rounded,
                  loading: _scanning,
                  onPressed: _escanear,
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),
                const SizedBox(height: 12),
                GhostButton(
                  label: 'Elegir de la galería',
                  icon: Icons.photo_library_rounded,
                  onPressed: _scanning ? null : () => _escanear(galeria: true),
                ).animate().fadeIn(delay: 400.ms),
              ],
              const SizedBox(height: 14),
              GhostButton(label: 'Cambiar pieza', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Brand.teal),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(color: Brand.muted))),
          ],
        ),
      );
}

/// Mensaje informativo cuando la pieza ya tiene un PDF asignado en el ERP.
class _YaTienePdf extends StatelessWidget {
  final String? file;
  const _YaTienePdf({this.file});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: Brand.warn.withValues(alpha: 0.6),
      color: Brand.warn.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_rounded, color: Brand.warn, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text('Esta pieza ya tiene un PDF asignado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.text)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (file != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Brand.bg.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, color: Brand.warn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(file!, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.text)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Para evitar duplicados o sobrescribir documentación existente, no es posible subir otro '
            'archivo a esta pieza.\n\n'
            'Si necesitas reemplazarlo, solicita a un administrador que elimine el PDF actual desde el '
            'ERP y luego vuelve a escanear.',
            style: TextStyle(color: Brand.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}
