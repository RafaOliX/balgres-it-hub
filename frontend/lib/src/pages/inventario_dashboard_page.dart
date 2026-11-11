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
          final porEstado = Map<String, dynamic>.from(d['por_estado'] as Map? ?? {});
          final porCat = Map<String, dynamic>.from(d['por_categoria'] as Map? ?? {});
          final porUbi = Map<String, dynamic>.from(d['por_ubicacion'] as Map? ?? {});
          final garantias = (d['garantias_por_vencer'] as List?) ?? [];
          final costo = (d['costo_total'] as num?)?.toDouble() ?? 0;
          final vencidas = (d['garantias_vencidas'] as num?)?.toInt() ?? 0;

          final tiles = <Widget>[
            KpiTile('Activos', '${d['total']}'),
            KpiTile('Unidades', '${d['unidades_totales']}'),
            KpiTile('Asignados', '${d['asignados']}', color: c.ok),
            KpiTile('Sin asignar', '${d['sin_asignar']}', color: c.warn),
            KpiTile('Borradores', '${d['borradores']}', color: c.muted),
            KpiTile('Costo total', '\$${costo.toStringAsFixed(0)}'),
            KpiTile('Garantías vencidas', '$vencidas', color: vencidas > 0 ? c.bad : c.muted),
            KpiTile('Vencen en 60 días', '${garantias.length}', color: garantias.isNotEmpty ? c.warn : c.muted),
          ];

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(32), children: [
                const Text('Resumen', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                const SizedBox(height: 24),
                Wrap(spacing: 24, runSpacing: 24, children: [for (final t in tiles) SizedBox(width: 220, child: t)]),
                const SizedBox(height: 40),
                _Bars('Por estado', porEstado),
                _Bars('Por categoría', porCat),
                _Bars('Por ubicación (top 8)', porUbi),
                if (garantias.isNotEmpty)
                  SwissSection('Garantías por vencer', [
                    for (final g in garantias)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                        child: Row(children: [
                          SizedBox(width: 110, child: Text('${g['tag']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          Expanded(child: Text('${g['equipo']}', overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted))),
                          Text('${g['vence']} · ${g['dias']} d',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: (g['dias'] as num) <= 15 ? c.bad : c.warn)),
                        ]),
                      ),
                  ]),
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
              child: Stack(children: [
                Container(height: 10, color: c.panel),
                FractionallySizedBox(widthFactor: (e.value as num).toInt() / max, child: Container(height: 10, color: c.accent)),
              ]),
            ),
            SizedBox(width: 48, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
    ]);
  }
}
