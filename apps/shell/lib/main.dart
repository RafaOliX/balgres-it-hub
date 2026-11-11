import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/layout.dart';
import 'core/theme.dart';
import 'pages/dashboard_page.dart';

// En web usa /api (relativo). En Android se pasa por --dart-define.
const _apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: '/api',
);

// Para Android, pasaremos la URL base completa. En Web, estará vacío.
const _hostBase = String.fromEnvironment(
  'HOST_BASE',
  defaultValue: '',
);

void main() => runApp(const BalgresItApp());

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
            GoRoute(path: 'nuevo', builder: (_, state) => AssetFormPage(template: state.extra is ItAsset ? state.extra as ItAsset : null)),
            GoRoute(
              path: 'detalle/:tag',
              builder: (_, state) => AssetDetailPage(assetTag: state.pathParameters['tag']!),
            ),
          ],
        ),
        GoRoute(path: '/categorias', builder: (_, __) => const CategoriesPage()),
        GoRoute(
          path: '/empleados',
          builder: (_, __) => const EmpleadosPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) => EmpleadoDetailPage(employeeId: int.parse(state.pathParameters['id']!)),
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
    if (kIsWeb) return;
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      final dio = Dio(BaseOptions(baseUrl: _hostBase));
      final r = await dio.get('/api/app/version');
      final latestVersion = r.data['version'];
      final apkUrl = r.data['apk_url'];
      if (latestVersion != pkgInfo.version && mounted) {
        showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
          title: const Text('Nueva versión disponible'),
          content: Text('La versión $latestVersion está disponible. Actualiza para seguir usando la app.'),
          actions: [
            TextButton(onPressed: () async {
              final url = Uri.parse('$_hostBase$apkUrl');
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
            }, child: const Text('Actualizar ahora'))
          ],
        ));
      }
    } catch (e) { debugPrint('Error updates: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        inventarioApiProvider.overrideWithValue(InventarioApi(baseUrl: _apiBase)),
        appHostBaseProvider.overrideWithValue(_hostBase),
      ],
      child: const _ThemedApp(),
    );
  }
}

class _ThemedApp extends ConsumerWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentProvider);
    return MaterialApp.router(
      title: 'Balgres IT Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
      themeMode: mode,
      routerConfig: _router,
    );
  }
}
