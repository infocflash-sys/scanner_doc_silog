import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
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
  String? _error;
  List<HistorialItem> _historial = [];

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
    if (!mounted) return;
    setState(() {
      _historial = h;
    });
  }

  Future<void> _cerrarSesion() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    if (salir == true) await AuthService.instance.cerrar(); // el AuthGate muestra el login
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Doc SILOG',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.text)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Brand.green.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Brand.green.withValues(alpha: 0.5)),
                                ),
                                child: Text(AppConfig.versionLabel,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: Brand.green)),
                              ),
                            ],
                          ),
                          Text(AuthService.instance.session.value?.nombre ?? 'Escáner inteligente de documentos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Brand.muted.withValues(alpha: 0.9))),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: const Icon(Icons.logout_rounded, color: Brand.muted),
                      onPressed: _cerrarSesion,
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
