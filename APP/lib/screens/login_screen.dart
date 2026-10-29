import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';

/// Pantalla de acceso con las credenciales del ERP (solo usuarios activos).
class LoginScreen extends StatefulWidget {
  /// `true` cuando se abre encima de otra pantalla (p. ej. al vencer la sesión durante un envío):
  /// al ingresar se cierra y devuelve `true`.
  final bool modal;
  const LoginScreen({super.key, this.modal = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _ver = false;
  String? _error;
  int _espera = 0; // segundos de bloqueo restantes
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _user.text = AuthService.instance.ultimoUsuario; // recuerda el último usuario
  }

  @override
  void dispose() {
    _timer?.cancel();
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _bloquear(int segundos) {
    _timer?.cancel();
    setState(() => _espera = segundos);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _espera = _espera - 1);
      if (_espera <= 0) {
        t.cancel();
        setState(() => _error = null);
      }
    });
  }

  String get _cuenta {
    final m = (_espera ~/ 60).toString().padLeft(2, '0');
    final s = (_espera % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _entrar() async {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Ingresa tu usuario y tu clave');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ApiService.instance.login(u, p);
      await AuthService.instance.iniciar(s, usuario: u); // el AuthGate pasa solo a la pantalla de inicio
      if (mounted && widget.modal) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.bloqueado && (e.retryAfter ?? 0) > 0) {
        _pass.clear();
        _bloquear(e.retryAfter!);
      }
      setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _espera > 0;
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LogoMark(size: 72).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.85, 0.85)),
                  const SizedBox(height: 16),
                  const Text('Doc SILOG',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Brand.text)),
                  Text('Escáner inteligente de documentos',
                      style: TextStyle(fontSize: 13, color: Brand.muted.withValues(alpha: 0.9))),
                  const SizedBox(height: 28),
                  AppCard(
                    borderColor: bloqueado ? Brand.warn.withValues(alpha: 0.5) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Iniciar sesión',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.text)),
                        const SizedBox(height: 4),
                        const Text('Usa tu usuario y clave del ERP.', style: TextStyle(color: Brand.muted)),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _user,
                          enabled: !_loading && !bloqueado,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.username],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          onSubmitted: (_) => _passFocus.requestFocus(),
                          onChanged: (_) {
                            if (_error != null && !bloqueado) setState(() => _error = null);
                          },
                          decoration: const InputDecoration(
                            hintText: 'Usuario',
                            prefixIcon: Icon(Icons.person_rounded, color: Brand.teal),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _pass,
                          focusNode: _passFocus,
                          enabled: !_loading && !bloqueado,
                          obscureText: !_ver,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          onSubmitted: (_) => _entrar(),
                          onChanged: (_) {
                            if (_error != null && !bloqueado) setState(() => _error = null);
                          },
                          decoration: InputDecoration(
                            hintText: 'Clave',
                            prefixIcon: const Icon(Icons.lock_rounded, color: Brand.teal),
                            suffixIcon: IconButton(
                              tooltip: _ver ? 'Ocultar clave' : 'Mostrar clave',
                              icon: Icon(_ver ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                  color: Brand.muted),
                              onPressed: () => setState(() => _ver = !_ver),
                            ),
                            errorText: bloqueado ? null : _error,
                            errorMaxLines: 3,
                          ),
                        ),
                        if (bloqueado) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(Icons.timer_rounded, color: Brand.warn, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Demasiados intentos. Podrás volver a intentar en $_cuenta.',
                                  style: const TextStyle(color: Brand.warn, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        GradientButton(
                          label: 'Ingresar',
                          icon: Icons.login_rounded,
                          loading: _loading,
                          onPressed: bloqueado ? null : _entrar,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.15),
                  const SizedBox(height: 16),
                  Text(AppConfig.versionLabel,
                      style: TextStyle(fontSize: 12, color: Brand.muted.withValues(alpha: 0.8))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
