import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'screens/blocked_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/app_status.dart';
import 'services/auth_service.dart';
import 'services/temp_cleaner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.cargar(); // recupera la sesión de 24 h si sigue vigente
  TempCleaner.clean(); // restos de sesiones anteriores
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Brand.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const DocSilogApp());
}

class DocSilogApp extends StatefulWidget {
  const DocSilogApp({super.key});

  @override
  State<DocSilogApp> createState() => _DocSilogAppState();
}

class _DocSilogAppState extends State<DocSilogApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.instance.verificarEstado();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuthService.instance.alVolver();
      ApiService.instance.verificarEstado();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doc SILOG',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
      // Si el servidor no habilita esta versión, una pantalla de bloqueo cubre todo.
      builder: (context, child) => ValueListenableBuilder<Bloqueo?>(
        valueListenable: AppStatus.instance.bloqueo,
        builder: (_, b, _) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (b != null) Positioned.fill(child: BlockedScreen(bloqueo: b)),
          ],
        ),
      ),
    );
  }
}
