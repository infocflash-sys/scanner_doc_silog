import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/scan_intro_painter.dart';
import 'home_screen.dart';

/// Bienvenida animada: muestra en ~3,4 s lo que hace la app. Tocar la pantalla la omite.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))
      ..forward().whenComplete(() => Future.delayed(const Duration(milliseconds: 450), _go));
  }

  void _go() {
    if (_gone || !mounted) return;
    _gone = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve c = Curves.easeOut]) =>
      c.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: GlowBackground(
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final title = _seg(0.55, 0.80);
                final tag = _seg(0.70, 0.92);
                final foot = _seg(0.85, 1.0);
                return Column(
                  children: [
                    const Spacer(flex: 3),
                    SizedBox(
                      width: 300,
                      height: 360,
                      child: CustomPaint(painter: ScanIntroPainter(_c.value)),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: title,
                      child: Transform.translate(
                        offset: Offset(0, 18 * (1 - title)),
                        child: ShaderMask(
                          shaderCallback: (r) => Brand.gradient.createShader(r),
                          child: const Text(
                            'Doc SILOG',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: tag,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - tag)),
                        child: const Text(
                          'ESCANEA  ·  MEJORA  ·  ARCHIVA',
                          style: TextStyle(
                            color: Brand.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    Opacity(
                      opacity: foot,
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 22),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 16, color: Brand.teal),
                            SizedBox(width: 8),
                            Text('Integrado con SILOG ERP',
                                style: TextStyle(color: Brand.muted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
