import 'package:balgres_it_contacts/balgres_it_contacts.dart';
import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:balgres_it_notas/balgres_it_notas.dart';
import 'package:balgres_it_redes/balgres_it_redes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/usuarios_page.dart';
import 'auth.dart';
import 'layout.dart';

/// Ruta -> permiso mínimo para entrar (el backend igual lo valida).
const _guards = {
  '/inventario': 'inventario.ver',
  '/categorias': 'inventario.ver',
  '/empleados': 'contactos.ver',
  '/redes': 'redes.ver',
  '/notas': 'notas.ver',
  '/usuarios': 'usuarios.ver',
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final a = ref.read(authProvider);
      final loc = state.uri.path;
      if (a.loading) return loc == '/splash' ? null : '/splash';
      final u = a.user;
      if (u == null) return loc == '/login' ? null : '/login';
      if (u.mustChangePassword) return loc == '/cambiar-clave' ? null : '/cambiar-clave';
      if (loc == '/login' || loc == '/splash') return '/';
      for (final e in _guards.entries) {
        if (loc.startsWith(e.key) && !u.can(e.value)) return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/cambiar-clave', builder: (_, __) => const ChangePasswordPage()),
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
          GoRoute(path: '/redes', builder: (_, __) => const RedesPage()),
          GoRoute(path: '/notas', builder: (_, __) => const NotasPage()),
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
          GoRoute(path: '/usuarios', builder: (_, __) => const UsuariosPage()),
        ],
      ),
    ],
  );
});
