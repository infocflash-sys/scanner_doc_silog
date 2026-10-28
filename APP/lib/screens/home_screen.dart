import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import 'pieza_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _retrying = false;
  String? _error;
  List<HistorialItem> _historial = [];
  List<PendingUpload> _pendientes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    final h = await StorageService.historial();
    final p = await StorageService.pendientes();
    if (!mounted) return;
    setState(() {
      _historial = h;
      _pendientes = p;
    });
  }

  Future<void> _validar() async {
    final id = _ctrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Ingresa el ID de la pieza');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await ApiService.instance.validarPieza(id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PiezaScreen(info: info)),
      );
      _ctrl.clear();
      _cargar();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reintentar() async {
    setState(() => _retrying = true);
    var ok = 0, descartados = 0;
    for (final p in await StorageService.pendientes()) {
      try {
        final r = await ApiService.instance.subirPdf(p.file, p.idPieza);
        await StorageService.addHistorial(HistorialItem(
          id: p.idPieza,
          cliente: '-',
          file: r.file,
          paginas: 0,
          fecha: DateTime.now(),
        ));
        await StorageService.borrarPendiente(p);
        ok++;
      } on ApiException catch (e) {
        if (e.offline) break;
        // Rechazo definitivo (p. ej. la pieza ya tiene PDF): se descarta para no reintentar eternamente.
        await StorageService.borrarPendiente(p);
        descartados++;
      }
    }
    await _cargar();
    if (!mounted) return;
    setState(() => _retrying = false);
    final extra = descartados > 0 ? ', $descartados descartado(s) (la pieza ya tenía PDF)' : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok + descartados == 0
          ? 'Sigue sin haber conexión. Se reintentará más tarde.'
          : '$ok enviado(s)$extra'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _cargar,
            color: Brand.green,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    const LogoMark(size: 52),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Doc SILOG',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.text)),
                        Text('Escáner inteligente de documentos',
                            style: TextStyle(fontSize: 13, color: Brand.muted.withValues(alpha: 0.9))),
                      ],
                    ),
                  ],
                ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2),
                const SizedBox(height: 28),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nueva digitalización',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.text)),
                      const SizedBox(height: 4),
                      const Text('Ingresa el ID de la pieza del ERP para comenzar.',
                          style: TextStyle(color: Brand.muted)),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 1),
                        onSubmitted: (_) => _validar(),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        decoration: InputDecoration(
                          hintText: 'Ej: 123456',
                          prefixIcon: const Icon(Icons.qr_code_2_rounded, color: Brand.teal),
                          errorText: _error,
                          errorMaxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GradientButton(
                        label: 'Validar y continuar',
                        icon: Icons.arrow_forward_rounded,
                        loading: _loading,
                        onPressed: _validar,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.15),
                if (_pendientes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    borderColor: Brand.warn.withValues(alpha: 0.5),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded, color: Brand.warn, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_pendientes.length} documento(s) por enviar',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.text)),
                              const Text('Guardados sin conexión',
                                  style: TextStyle(color: Brand.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                        _retrying
                            ? const SizedBox(
                                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                            : TextButton(onPressed: _reintentar, child: const Text('Enviar')),
                      ],
                    ),
                  ).animate().fadeIn(),
                ],
                if (_historial.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('Recientes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Brand.text)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _historial.length; i++)
                    _HistorialTile(item: _historial[i])
                        .animate()
                        .fadeIn(delay: (250 + i * 60).ms)
                        .slideX(begin: 0.1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorialTile extends StatelessWidget {
  final HistorialItem item;
  const _HistorialTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final f = item.fecha;
    String two(int n) => n.toString().padLeft(2, '0');
    final fecha = '${two(f.day)}/${two(f.month)} ${two(f.hour)}:${two(f.minute)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Brand.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Brand.green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.file, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.text)),
                Text(item.cliente == '-' ? 'Pieza ${item.id}' : item.cliente,
                    style: const TextStyle(color: Brand.muted, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(fecha, style: const TextStyle(color: Brand.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
