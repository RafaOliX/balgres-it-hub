import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../ui/swiss.dart';

class InventarioDashboardPage extends ConsumerWidget {
  const InventarioDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(dashboardProvider))],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) {
          Map<String, dynamic> m(String k) => Map<String, dynamic>.from(d[k] as Map? ?? {});
          final tiles = <Widget>[
            KpiTile('Activos', '${d['total']}', icon: Icons.inventory_2_outlined),
            KpiTile('Unidades', '${d['unidades_totales']}', icon: Icons.numbers, color: c.accent2),
            KpiTile('Asignados', '${d['asignados']}', icon: Icons.person_outline, color: c.ok),
            KpiTile('Sin asignar', '${d['sin_asignar']}', icon: Icons.person_off_outlined, color: c.warn),
            KpiTile('Borradores', '${d['borradores']}', icon: Icons.edit_note, color: c.muted),
          ];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(32), children: [
                const Text('Resumen', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                const SizedBox(height: 24),
                Wrap(spacing: 18, runSpacing: 18, children: [for (final t in tiles) SizedBox(width: 190, child: t)]),
                const SizedBox(height: 32),
                _Bars('Por estado', m('por_estado')),
                _Bars('Por categoría', m('por_categoria')),
                _Bars('Por ubicación (top 8)', m('por_ubicacion')),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _Bars(this.title, this.data);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final c = context.sw;
    final max = data.values.map((v) => (v as num).toInt()).fold<int>(1, (a, b) => b > a ? b : a);
    return SwissSection(title, [
      for (final e in data.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 170, child: Text(e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: (e.value as num).toInt() / max, minHeight: 10, backgroundColor: c.panel, valueColor: AlwaysStoppedAnimation(c.accent)),
              ),
            ),
            SizedBox(width: 48, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
    ]);
  }
}
