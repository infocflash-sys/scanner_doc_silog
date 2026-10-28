import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'screens/splash_screen.dart';
import 'services/temp_cleaner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  TempCleaner.clean(); // restos de sesiones anteriores
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Brand.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const DocSilogApp());
}

class DocSilogApp extends StatelessWidget {
  const DocSilogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doc SILOG',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}
