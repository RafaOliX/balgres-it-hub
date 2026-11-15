import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth.dart';
import 'brand.dart';

class AppLayout extends ConsumerWidget {
  final Widget child;
  const AppLayout({super.key, required this.child});

  static const _all = [
    _Dest(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Resumen', path: '/'),
    _Dest(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventario', path: '/inventario', perm: 'inventario.ver'),
    _Dest(icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Empleados', path: '/empleados', perm: 'contactos.ver'),
    _Dest(icon: Icons.lan_outlined, selectedIcon: Icons.lan, label: 'Redes', path: '/redes', perm: 'redes.ver'),
    _Dest(icon: Icons.sticky_note_2_outlined, selectedIcon: Icons.sticky_note_2, label: 'Notas', path: '/notas', perm: 'notas.ver'),
    _Dest(icon: Icons.admin_panel_settings_outlined, selectedIcon: Icons.admin_panel_settings, label: 'Usuarios', path: '/usuarios', perm: 'usuarios.ver'),
  ];

  int _indexFor(String location, List<_Dest> ds) {
    final loc = location.startsWith('/categorias') ? '/inventario' : location;
    final i = ds.indexWhere((d) => d.path != '/' && loc.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final ds = _all.where((d) => d.perm == null || (user?.can(d.perm!) ?? false)).toList();
    if (ds.length < 2) return Scaffold(body: SafeArea(child: child)); // los nav bars exigen 2+ destinos

    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFor(location, ds);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (wide) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 96,
              decoration: cardDeco(context, radius: 22),
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (i) => context.go(ds[i].path),
                labelType: NavigationRailLabelType.all,
                minWidth: 84,
                leading: const Padding(padding: EdgeInsets.only(top: 22, bottom: 26), child: BrandLogo(height: 44)),
                trailing: const Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [UserMenuButton(), ThemeToggleButton()]),
                    ),
                  ),
                ),
                destinations: ds.map((d) => NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label))).toList(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1440), child: child))),
          ]),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(ds[i].path),
        destinations: ds.map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)).toList(),
      ),
    );
  }
}

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;
  final String? perm;
  const _Dest({required this.icon, required this.selectedIcon, required this.label, required this.path, this.perm});
}
