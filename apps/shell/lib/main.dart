import 'package:flutter/foundation.dart';

import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/layout.dart';
import 'core/theme.dart';
import 'pages/dashboard_page.dart';

// En producción real, esto será la IP del servidor (ej. http://192.168.1.100/api)
const _apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000/api', 
);

void main() {
  runApp(const BalgresItApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (_, __, child) => AppLayout(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(
          path: '/inventario',
          builder: (_, __) => const InventarioPage(),
          routes: [
            GoRoute(path: 'nuevo', builder: (_, __) => const AssetFormPage()),
            GoRoute(
              path: 'detalle/:tag',
              builder: (_, state) => AssetDetailPage(assetTag: state.pathParameters['tag']!),
            ),
          ],
        ),
      ],
    ),
  ],
);

class BalgresItApp extends StatefulWidget {
  const BalgresItApp({super.key});
  @override
  State<BalgresItApp> createState() => _BalgresItAppState();
}

class _BalgresItAppState extends State<BalgresItApp> {
  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    // Evitar que corra en Web
    if (kIsWeb) return;

    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      final dio = Dio(BaseOptions(baseUrl: _apiBase.replaceAll('/api', ''))); 
      
      final r = await dio.get('/api/app/version');
      final latestVersion = r.data['version'];
      final apkUrl = r.data['apk_url'];
      final currentVersion = pkgInfo.version;

      if (latestVersion != currentVersion) {
        // Si estamos en la app, mostrar diálogo
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Nueva versión disponible'),
              content: Text('La versión $latestVersion está disponible. Actualiza para seguir usando la app.'),
              actions: [
                TextButton(
                  onPressed: () async {
                    final url = Uri.parse('${_apiBase.replaceAll('/api', '')}$apkUrl');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Actualizar ahora'),
                )
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error chequeando actualización: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        inventarioApiProvider.overrideWithValue(
          InventarioApi(baseUrl: _apiBase),
        ),
      ],
      child: MaterialApp.router(
        title: 'Balgres IT Hub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
