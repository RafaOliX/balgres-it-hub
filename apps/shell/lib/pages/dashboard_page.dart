import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:balgres_it_redes/balgres_it_redes.dart';
import '../core/dashboard_prefs.dart';

import '../core/auth.dart';
import '../core/brand.dart';

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String _hoy() {
  final n = DateTime.now();
  return 'Hoy es ${_dias[n.weekday - 1]}, ${n.day} de ${_meses[n.month - 1]} de ${n.year}';
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(dashboardProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;

    return ListView(padding: EdgeInsets.all(mobile ? 16 : 28), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (mobile) ...[const BrandLogo(height: 38), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hola, equipo de TI', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1)),
            const SizedBox(height: 4),
            Text(_hoy(), style: TextStyle(fontSize: 13, color: c.muted)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.tune), tooltip: 'Personalizar', onPressed: () => showDashCustomizeDialog(context)),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(dashboardProvider)),
        if (mobile) const UserMenuButton(),
        if (mobile) const ThemeToggleButton(),
        if (!mobile) ...[
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: () => context.go('/inventario'), icon: const Icon(Icons.add, size: 18), label: const Text('Ir al inventario')),
        ],
      ]),
      const SizedBox(height: 24),
      async.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Row(children: [
          Expanded(child: Text('No se pudo cargar: ${apiError(e)}', style: TextStyle(color: c.bad))),
          OutlinedButton(onPressed: () => ref.invalidate(dashboardProvider), child: const Text('Reintentar')),
        ]),
        data: (d) => _Content(d: d, wide: !mobile),
      ),
    ]);
  }
}


class _Content extends ConsumerWidget {
  final Map<String, dynamic> d;
  final bool wide;
  const _Content({required this.d, required this.wide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final prefs = ref.watch(dashPrefsProvider);
    final items = (ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[]).where((a) => !a.isDraft).toList();
    final segs = ref.watch(segmentsProvider).valueOrNull ?? const <Segment>[];

    final total = (d['total'] as num?)?.toInt() ?? 0;
    final porEstado = Map<String, dynamic>.from(d['por_estado'] as Map? ?? {});
    final porCat = Map<String, dynamic>.from(d['por_categoria'] as Map? ?? {});
    int n(String k) => (porEstado[k] as num?)?.toInt() ?? 0;
    double pr(int v) => total == 0 ? 0 : v / total;
    String pct(int v) => '${(pr(v) * 100).round()}%';
    int maxOf(Iterable<num> v) => v.map((x) => x.toInt()).fold<int>(1, (a, b) => b > a ? b : a);

    Widget bar(String label, int value, int max, {double labelW = 140}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: labelW, child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: value / max, minHeight: 10, backgroundColor: c.panel, valueColor: AlwaysStoppedAnimation(c.accent)),
              ),
            ),
            SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        );

    // ---- computadoras en uso (categoría cuyo nombre contiene "comput")
    final pcs = items.where((a) => normalizeText(a.category).contains('comput')).toList();
    final pcsUso = pcs.where((a) => (a.assignedTo ?? '').trim().isNotEmpty).length;

    // ---- asignaciones: top responsables
    final porResp = <String, int>{};
    for (final a in items) {
      final w = (a.assignedTo ?? '').trim();
      if (w.isNotEmpty) porResp[w] = (porResp[w] ?? 0) + 1;
    }
    final top = (porResp.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8).toList();

    final blocks = <String, ({Widget w, bool full})>{
      'estados': (
        full: true,
        w: Wrap(spacing: 18, runSpacing: 14, children: [
          for (final h in [
            ('Operativos', n('Operativo'), dark ? const Color(0xFF1B2A9E) : kBrandNavy, Icons.check_circle_outline),
            ('En revisión', n('En Revisión'), kBrandCyan, Icons.build_outlined),
            ('Retirados', n('Retirado'), kBrandCoral, Icons.archive_outlined),
          ])
            SizedBox(
              width: wide ? 300 : double.infinity,
              child: HeroCard(title: h.$1, value: '${h.$2}', caption: pct(h.$2), progress: pr(h.$2), color: h.$3, icon: h.$4),
            ),
        ]),
      ),
      'stats': (
        full: true,
        w: LayoutBuilder(builder: (context, cs) {
          final cols = cs.maxWidth >= 640 ? 3 : 2;
          final w = (cs.maxWidth - 14 * (cols - 1)) / cols;
          final tiles = <Widget>[
            KpiTile('Activos', '$total', icon: Icons.inventory_2_outlined),
            KpiTile('Unidades', '${d['unidades_totales']}', icon: Icons.numbers, color: c.accent2),
            KpiTile('Asignados', '${d['asignados']}', icon: Icons.person_outline, color: c.ok),
            KpiTile('Sin asignar', '${d['sin_asignar']}', icon: Icons.person_off_outlined, color: c.warn),
            KpiTile('Borradores', '${d['borradores']}', icon: Icons.edit_note, color: c.muted),
          ];
          return Wrap(spacing: 14, runSpacing: 14, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
      ),
      'en_uso': (
        full: false,
        w: SwissSection('Computadoras en uso', [
          if (pcs.isEmpty) Text('No hay equipos en una categoría de computadoras.', style: TextStyle(color: c.muted)),
          if (pcs.isNotEmpty) ...[
            bar('En uso', pcsUso, pcs.length),
            bar('Disponibles', pcs.length - pcsUso, pcs.length),
            const SizedBox(height: 4),
            Text('$pcsUso de ${pcs.length} computadoras tienen responsable', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ]),
      ),
      'asignaciones': (
        full: false,
        w: SwissSection('Asignaciones por responsable', [
          if (top.isEmpty) Text('Sin equipos asignados', style: TextStyle(color: c.muted)),
          for (final e in top) bar(e.key, e.value, maxOf(top.map((x) => x.value))),
        ]),
      ),
      'redes': (
        full: false,
        w: SwissSection('Red / IPs por segmento', [
          if (segs.isEmpty) Text('Sin segmentos registrados', style: TextStyle(color: c.muted)),
          for (final s in segs.take(8)) ...[
            bar(s.name ?? s.cidr, s.usadas, 254),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('En línea ${s.enLinea} · Sin respuesta ${s.sinRespuesta} · Libres ${s.libres}', style: TextStyle(fontSize: 11, color: c.muted)),
            ),
          ],
        ]),
      ),
      'categorias': (
        full: false,
        w: SwissSection('Por categoría', [
          if (porCat.isEmpty) Text('Sin datos', style: TextStyle(color: c.muted)),
          for (final e in porCat.entries.take(8)) bar(e.key, (e.value as num).toInt(), maxOf(porCat.values.cast<num>())),
        ]),
      ),
      'modulos': (
        full: false,
        w: SwissSection('Módulos', [
          _ModuleRow(index: '01', title: 'Inventario', subtitle: 'Activos de TI', onTap: () => context.go('/inventario')),
          _ModuleRow(index: '02', title: 'Empleados', subtitle: 'Custodia', onTap: () => context.go('/empleados')),
          _ModuleRow(index: '03', title: 'Redes', subtitle: 'IPs y escaneo', onTap: () => context.go('/redes')),
        ]),
      ),
    };

    final shown = [for (final id in prefs.visible) if (blocks[id] != null) blocks[id]!];

    return LayoutBuilder(builder: (context, cs) {
      final half = wide ? (cs.maxWidth - 18) / 2 : cs.maxWidth;
      return Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [for (final b in shown) SizedBox(width: b.full ? cs.maxWidth : half, child: b.w)],
      );
    });
  }
}

class _ModuleRow extends StatelessWidget {
  final String index, title, subtitle;
  final VoidCallback? onTap;
  const _ModuleRow({required this.index, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          SizedBox(width: 32, child: Text(index, style: TextStyle(fontSize: 12, color: c.muted))),
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: enabled ? c.ink : c.muted))),
          Text(subtitle, style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 16, color: enabled ? c.accent : c.edge),
        ]),
      ),
    );
  }
}
