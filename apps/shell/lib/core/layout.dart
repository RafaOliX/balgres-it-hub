import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'brand.dart';

class AppLayout extends StatelessWidget {
  final Widget child;
  const AppLayout({super.key, required this.child});

  static const _destinations = [
    _Dest(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Resumen', path: '/'),
    _Dest(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventario', path: '/inventario'),
    _Dest(icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Empleados', path: '/empleados'),
    _Dest(icon: Icons.lan_outlined, selectedIcon: Icons.lan, label: 'Redes', path: '/redes'),
  ];

  int _indexFor(String location) {
    if (location.startsWith('/empleados')) return 2;
    if (location.startsWith('/redes')) return 3;
    if (location.startsWith('/inventario') || location.startsWith('/categorias')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFor(location);
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
                onDestinationSelected: (i) => context.go(_destinations[i].path),
                labelType: NavigationRailLabelType.all,
                minWidth: 84,
                leading: const Padding(padding: EdgeInsets.only(top: 22, bottom: 26), child: BrandLogo(height: 44)),
                trailing: const Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.only(bottom: 16), child: ThemeToggleButton()))),
                destinations: _destinations
                    .map((d) => NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)))
                    .toList(),
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
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: _destinations
            .map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label))
            .toList(),
      ),
    );
  }
}

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;
  const _Dest({required this.icon, required this.selectedIcon, required this.label, required this.path});
}
