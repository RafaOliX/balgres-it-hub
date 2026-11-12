import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(dashboardProvider)),
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

class _Content extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool wide;
  const _Content({required this.d, required this.wide});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = (d['total'] as num?)?.toInt() ?? 0;
    final porEstado = Map<String, dynamic>.from(d['por_estado'] as Map? ?? {});
    final porCat = Map<String, dynamic>.from(d['por_categoria'] as Map? ?? {});
    int n(String k) => (porEstado[k] as num?)?.toInt() ?? 0;
    double pr(int v) => total == 0 ? 0 : v / total;
    String pct(int v) => '${(pr(v) * 100).round()}%';

    final hero = <Widget>[
      HeroCard(title: 'Operativos', value: '${n('Operativo')}', caption: pct(n('Operativo')), progress: pr(n('Operativo')), color: dark ? const Color(0xFF1B2A9E) : kBrandNavy, icon: Icons.check_circle_outline),
      HeroCard(title: 'En revisión', value: '${n('En Revisión')}', caption: pct(n('En Revisión')), progress: pr(n('En Revisión')), color: kBrandCyan, icon: Icons.build_outlined),
      HeroCard(title: 'Retirados', value: '${n('Retirado')}', caption: pct(n('Retirado')), progress: pr(n('Retirado')), color: kBrandCoral, icon: Icons.archive_outlined),
    ];

    final tiles = <Widget>[
      KpiTile('Activos', '$total', icon: Icons.inventory_2_outlined),
      KpiTile('Unidades', '${d['unidades_totales']}', icon: Icons.numbers, color: c.accent2),
      KpiTile('Asignados', '${d['asignados']}', icon: Icons.person_outline, color: c.ok),
      KpiTile('Sin asignar', '${d['sin_asignar']}', icon: Icons.person_off_outlined, color: c.warn),
      KpiTile('Borradores', '${d['borradores']}', icon: Icons.edit_note, color: c.muted),
    ];

    final maxCat = porCat.values.map((v) => (v as num).toInt()).fold<int>(1, (a, b) => b > a ? b : a);

    final main = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      wide
          ? Row(children: [for (var i = 0; i < hero.length; i++) ...[Expanded(child: hero[i]), if (i < hero.length - 1) const SizedBox(width: 18)]])
          : Column(children: [for (final h in hero) Padding(padding: const EdgeInsets.only(bottom: 14), child: h)]),
      const SizedBox(height: 28),
      const SectionLabel('Estadísticas'),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, cs) {
        final cols = cs.maxWidth >= 640 ? 3 : 2;
        final w = (cs.maxWidth - 14 * (cols - 1)) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      }),
      const SizedBox(height: 28),
      SwissSection('Por categoría', [
        if (porCat.isEmpty) Text('Sin datos', style: TextStyle(color: c.muted)),
        for (final e in porCat.entries.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 140, child: Text(e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: (e.value as num).toInt() / maxCat, minHeight: 10, backgroundColor: c.panel, valueColor: AlwaysStoppedAnimation(c.accent)),
                ),
              ),
              SizedBox(width: 44, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
      ]),
    ]);

    final side = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwissSection('Módulos', [
        _ModuleRow(index: '01', title: 'Inventario', subtitle: 'Activos de TI', onTap: () => context.go('/inventario')),
        const _ModuleRow(index: '02', title: 'Tickets', subtitle: 'Próximamente'),
        const _ModuleRow(index: '03', title: 'Licencias', subtitle: 'Próximamente'),
        const _ModuleRow(index: '04', title: 'Usuarios', subtitle: 'Próximamente'),
      ]),
    ]);

    return wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: main), const SizedBox(width: 24), SizedBox(width: 340, child: side)])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [main, const SizedBox(height: 24), side]);
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
