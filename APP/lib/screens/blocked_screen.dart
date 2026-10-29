import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/app_status.dart';
import '../widgets/common.dart';

/// Cubre toda la app cuando el servidor no habilita esta versión.
class BlockedScreen extends StatefulWidget {
  final Bloqueo bloqueo;
  const BlockedScreen({super.key, required this.bloqueo});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  bool _checking = false;
  bool _copiado = false;

  Future<void> _reintentar() async {
    setState(() => _checking = true);
    await ApiService.instance.verificarEstado(); // si ya está habilitada, el bloqueo se levanta solo
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bloqueo;
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AppCard(
                borderColor: Brand.warn.withValues(alpha: 0.5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_rounded, size: 84, color: Brand.warn)
                        .animate()
                        .scale(begin: const Offset(0.3, 0.3), duration: 500.ms, curve: Curves.elasticOut),
                    const SizedBox(height: 16),
                    const Text('Versión no habilitada',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.text)),
                    const SizedBox(height: 12),
                    Text(b.mensaje,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Brand.muted, height: 1.45)),
                    if (b.url.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SelectableText(b.url,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Brand.teal, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      GhostButton(
                        label: _copiado ? 'Enlace copiado' : 'Copiar enlace de descarga',
                        icon: _copiado ? Icons.check_rounded : Icons.copy_rounded,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: b.url));
                          if (mounted) setState(() => _copiado = true);
                        },
                      ),
                    ],
                    const SizedBox(height: 22),
                    GradientButton(
                      label: 'Reintentar',
                      icon: Icons.refresh_rounded,
                      loading: _checking,
                      onPressed: _reintentar,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
