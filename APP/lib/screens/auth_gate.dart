import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Muestra el login si no hay sesión vigente (nunca entró, la cerró o venció a las 24 h).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Session?>(
      valueListenable: AuthService.instance.session,
      builder: (_, s, _) => s == null ? const LoginScreen() : HomeScreen(key: ValueKey(s.uid)),
    );
  }
}
