import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/filters.dart';
import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/search_select.dart';

const _kKinds = ['Sede', 'Edificio', 'Piso', 'Área', 'Oficina', 'Cuarto de servidores', 'Rack', 'Bodega', 'Laboratorio', 'Sala de reuniones'];

String _nextKind(String? k) {
  final n = normalizeText(k ?? '');
  if (n.contains('sede')) return 'Área';
  if (n.contains('edificio')) return 'Piso';
  if (n.contains('piso')) return 'Área';
  if (n.contains('area')) return 'Oficina';
  if (n.contains('oficina') || n.contains('servidores')) return 'Rack';
  return '';
}

IconData _kindIcon(String? k) {
  final n = normalizeText(k ?? '');
  if (n.contains('sede') || n.contains('edificio')) return Icons.apartment;
  if (n.contains('piso')) return Icons.layers_outlined;
  if (n.contains('area')) return Icons.domain;
  if (n.contains('oficina') || n.contains('sala')) return Icons.meeting_room_outlined;
  if (n.contains('rack') || n.contains('servidor')) return Icons.dns_outlined;
  if (n.contains('bodega')) return Icons.warehouse_outlined;
  return Icons.place_outlined;
}

/// Ubicaciones como árbol: cada nivel tiene su propio "+" para agregar dentro.
class CatalogosPage extends ConsumerStatefulWidget {
  const CatalogosPage({super.key});
  @override
  ConsumerState<CatalogosPage> createState() => _CatalogosPageState();
}

class _CatalogosPageState extends ConsumerState<CatalogosPage> {
  final Set<int> _collapsed = {};
  String _q = '';

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Map<int?, List<Location>> _kids(List<Location> all) {
    final m = <int?, List<Location>>{};
    for (final l in all) {
      m.putIfAbsent(l.parentId, () => []).add(l);
    }
    for (final v in m.values) {
      v.sort((a, b) => normalizeText(a.name).compareTo(normalizeText(b.name)));
    }
    return m;
  }

  Set<int> _descendants(int id, Map<int?, List<Location>> kids) {
    final out = <int>{};
    void go(int p) {
      for (final c in kids[p] ?? const <Location>[]) {
        if (out.add(c.id)) go(c.id);
      }
    }
    go(id);
    return out;
  }

  Future<void> _dialog(List<Location> all, {Location? loc, Location? parent}) async {
    final kids = _kids(all);
    final blocked = loc == null ? <int>{} : {loc.id, ..._descendants(loc.id, kids)};
    final name = TextEditingController(text: loc?.name ?? '');
    final kind = TextEditingController(text: loc?.kind ?? (parent != null ? _nextKind(parent.kind) : ''));
    Location? par = loc != null ? all.where((l) => l.id == loc.parentId).firstOrNull : parent;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final c = ctx.sw;
          final nm = name.text.trim();
          final preview = [if (par != null) par!.fullName, if (nm.isNotEmpty) nm].join(' › ');
          return AlertDialog(
            title: Text(loc == null ? (par == null ? 'Nueva ubicación principal' : 'Agregar dentro de "${par!.name}"') : 'Editar ubicación'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: name, autofocus: true, onChanged: (_) => setM(() {}), decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Rack 1')),
                  const SizedBox(height: 12),
                  SuggestField(controller: kind, label: 'Tipo (opcional)', suggestions: () => _kKinds),
                  const SizedBox(height: 12),
                  SearchSelect<Location>(
                    label: 'Dentro de (vacío = nivel principal)',
                    value: par,
                    options: all.where((l) => !blocked.contains(l.id)).toList(),
                    display: (l) => l.fullName,
                    subtitle: (l) => l.kind ?? '',
                    onChanged: (l) => setM(() => par = l),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SE GUARDARÁ COMO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.muted)),
                      const SizedBox(height: 4),
                      Text(preview.isEmpty ? '—' : preview, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  final body = {'name': name.text.trim(), 'kind': kind.text.trim(), 'parent_id': par?.id};
                  try {
                    final api = ref.read(inventarioApiProvider);
                    if (loc == null) {
                      await api.crearUbicacion(body);
                    } else {
                      await api.actualizarUbicacion(loc.id, body);
                    }
                    ref.invalidate(ubicacionesProvider);
                    ref.invalidate(inventarioListProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(Location l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ubicación'),
        content: Text('¿Eliminar "${l.fullName}"? Solo se puede si no tiene sububicaciones ni equipos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: context.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminarUbicacion(l.id);
      ref.invalidate(ubicacionesProvider);
    } catch (e) {
      _snack(apiError(e));
    }
  }

  Future<void> _unificar() async {
    try {
      final r = await ref.read(inventarioApiProvider).importarUbicaciones();
      ref.invalidate(ubicacionesProvider);
      ref.invalidate(inventarioListProvider);
      _snack('${r['ubicaciones_creadas']} ubicaciones creadas, ${r['activos_vinculados']} activos vinculados');
    } catch (e) {
      _snack(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final async = ref.watch(ubicacionesProvider);
    final items = ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
    final all = async.valueOrNull ?? const <Location>[];
    final kids = _kids(all);

    final direct = <int, int>{};
    for (final a in items) {
      if (a.locationId != null && !a.isDraft) direct[a.locationId!] = (direct[a.locationId!] ?? 0) + 1;
    }
    final memo = <int, int>{};
    int total(int id) => memo.putIfAbsent(id, () => (direct[id] ?? 0) + (kids[id] ?? const <Location>[]).fold<int>(0, (s, k) => s + total(k.id)));

    // búsqueda: coincidencias + sus ancestros
    Set<int>? visible;
    final terms = normalizeText(_q.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isNotEmpty) {
      final byId = {for (final l in all) l.id: l};
      visible = <int>{};
      for (final l in all) {
        final hay = normalizeText('${l.fullName} ${l.kind ?? ''}');
        if (terms.every(hay.contains)) {
          Location? cur = l;
          while (cur != null && visible.add(cur.id)) {
            cur = cur.parentId == null ? null : byId[cur.parentId];
          }
        }
      }
    }

    final rows = <(Location, int)>[];
    void walk(int? parent, int depth) {
      for (final l in kids[parent] ?? const <Location>[]) {
        if (visible != null && !visible.contains(l.id)) continue;
        rows.add((l, depth));
        if (visible != null || !_collapsed.contains(l.id)) walk(l.id, depth + 1);
      }
    }
    walk(null, 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ubicaciones'),
        actions: [
          IconButton(icon: const Icon(Icons.unfold_less), tooltip: 'Contraer todo', onPressed: () => setState(() => _collapsed.addAll(all.where((l) => (kids[l.id] ?? const []).isNotEmpty).map((l) => l.id)))),
          IconButton(icon: const Icon(Icons.unfold_more), tooltip: 'Expandir todo', onPressed: () => setState(_collapsed.clear)),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton.icon(onPressed: () => _dialog(all), icon: const Icon(Icons.add, size: 18), label: const Text('Ubicación principal')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.account_tree_outlined, color: c.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Organiza de lo general a lo particular: Sede → Área → Oficina → Rack. Usa el botón + de cada fila para agregar un nivel dentro de ella.',
                      style: TextStyle(fontSize: 13, color: c.ink)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _unificar, icon: const Icon(Icons.auto_fix_high, size: 18), label: const Text('Unificar desde activos')),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'Buscar ubicación…', prefixIcon: Icon(Icons.search, size: 20))),
            const SizedBox(height: 16),
            if (async.isLoading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (all.isEmpty)
              Padding(padding: const EdgeInsets.all(40), child: EmptyState(icon: Icons.place_outlined, title: 'Aún no hay ubicaciones', subtitle: 'Crea la primera sede o unifícalas desde los activos.', action: 'Crear ubicación principal', onAction: () => _dialog(all)))
            else
              Container(
                decoration: cardDeco(context),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final r in rows) _row(c, r.$1, r.$2, total(r.$1.id), (kids[r.$1.id] ?? const []).isNotEmpty, all),
                  if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Sin resultados', style: TextStyle(color: c.muted))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _row(SwissColors c, Location l, int depth, int n, bool hasKids, List<Location> all) {
    final collapsed = _collapsed.contains(l.id);
    return Container(
      padding: EdgeInsets.fromLTRB(12 + depth * 26.0, 6, 8, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line)), color: depth == 0 ? c.panel.withValues(alpha: 0.6) : null),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: hasKids
              ? IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  tooltip: collapsed ? 'Expandir' : 'Contraer',
                  icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
                  onPressed: () => setState(() => collapsed ? _collapsed.remove(l.id) : _collapsed.add(l.id)),
                )
              : (depth > 0 ? Icon(Icons.subdirectory_arrow_right, size: 16, color: c.edge) : null),
        ),
        const SizedBox(width: 6),
        Icon(_kindIcon(l.kind), size: 20, color: depth == 0 ? c.accent : c.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: depth == 0 ? FontWeight.w800 : FontWeight.w600)),
            if ((l.kind ?? '').isNotEmpty) Text(l.kind!, style: TextStyle(fontSize: 11, color: c.muted)),
          ]),
        ),
        if (n > 0)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text('$n equipo${n == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
          ),
        IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), tooltip: 'Agregar dentro de "${l.name}"', onPressed: () => _dialog(all, parent: l)),
        IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar o mover', onPressed: () => _dialog(all, loc: l)),
        IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => _delete(l)),
      ]),
    );
  }
}
