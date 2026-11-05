import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/layout.dart';
import 'core/theme.dart';
import 'pages/dashboard_page.dart';

const _apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000/api',
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
            GoRoute(path: 'nuevo', builder: (_, __) => const AssetFormPage()),
          ],
        ),
      ],
    ),
  ],
);

class BalgresItApp extends StatelessWidget {
  const BalgresItApp({super.key});

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
