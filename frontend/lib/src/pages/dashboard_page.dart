import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

const _border = Color(0xFFE5E7EB);

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Dashboard'), backgroundColor: Colors.white, elevation: 0.5,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(dashboardProvider))],
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

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _Kpi('Activos', '${d['total']}', Icons.inventory_2_outlined, Colors.indigo),
                  _Kpi('Unidades', '${d['unidades_totales']}', Icons.numbers, Colors.blueGrey),
                  _Kpi('Asignados', '${d['asignados']}', Icons.person_outline, Colors.green),
                  _Kpi('Sin asignar', '${d['sin_asignar']}', Icons.person_off_outlined, Colors.orange),
                  _Kpi('Borradores', '${d['borradores']}', Icons.edit_note, Colors.grey),
                  _Kpi('Costo total', '\$${costo.toStringAsFixed(2)}', Icons.attach_money, Colors.teal),
                  _Kpi('Garantías vencidas', '$vencidas', Icons.warning_amber_rounded, vencidas > 0 ? Colors.red : Colors.grey),
                  _Kpi('Vencen en 60 días', '${garantias.length}', Icons.schedule, garantias.isNotEmpty ? Colors.orange : Colors.grey),
                ]),
                const SizedBox(height: 24),
                _Bars('Por estado', porEstado),
                _Bars('Por categoría', porCat),
                _Bars('Por ubicación (top 8)', porUbi),
                if (garantias.isNotEmpty)
                  _Box('Garantías por vencer', garantias.map<Widget>((g) {
                    final dias = (g['dias'] as num).toInt();
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.shield_outlined, color: dias <= 15 ? Colors.red : Colors.orange),
                      title: Text('${g['tag']} · ${g['equipo']}'),
                      trailing: Text('${g['vence']} ($dias d)', style: const TextStyle(fontSize: 12)),
                    );
                  }).toList()),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 220, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
        ]),
      );
}

class _Box extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Box(this.title, this.children);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280), letterSpacing: 0.8)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );
}

class _Bars extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _Bars(this.title, this.data);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final max = data.values.map((v) => (v as num).toInt()).fold<int>(1, (a, b) => b > a ? b : a);
    return _Box(title, data.entries.map<Widget>((e) {
      final v = (e.value as num).toInt();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 170, child: Text(e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: v / max, minHeight: 14, backgroundColor: const Color(0xFFF3F4F6), color: const Color(0xFF4F46E5)),
            ),
          ),
          SizedBox(width: 44, child: Text('$v', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
    }).toList());
  }
}
