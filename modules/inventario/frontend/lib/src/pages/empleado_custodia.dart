import 'package:balgres_it_contacts/balgres_it_contacts.dart'
    show Employee, EmployeeCtx, EmployeeExtension, EmployeeMenuEntry, empleadosProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/filters.dart';
import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';
import '../widgets/search_select.dart';
import 'acta_templates_page.dart';

/// Lo que inventario añade a la lista y a la ficha de empleados (custodia y actas).
final inventarioEmployeeExtension = EmployeeExtension(
  menu: [
    EmployeeMenuEntry('Plantillas de acta', (context, ref) async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ActaTemplatesPage()));
      ref.invalidate(actaTemplatesProvider);
    }),
    EmployeeMenuEntry('Imprimir hoja en blanco', (context, ref) async {
      final t = await showActaPicker(context, title: 'Hoja en blanco: elige la plantilla');
      if (t == null || !context.mounted) return;
      try {
        await ref.read(inventarioApiProvider).descargarActaPlantilla(t.id, name: t.name);
      } catch (e) {
        _snack(context, 'Error: ${apiError(e)}');
      }
    }),
    EmployeeMenuEntry('Importar desde activos', (context, ref) async {
      try {
        final r = await ref.read(inventarioApiProvider).importarEmpleados();
        ref.invalidate(empleadosProvider);
        _snack(context, '${r['empleados_creados']} empleados creados, ${r['activos_vinculados']} activos vinculados');
      } catch (e) {
        _snack(context, 'Error: ${apiError(e)}');
      }
    }),
  ],
  appBarActions: (context, c) => [_ActaButton(c)],
  actions: _actions,
  body: (context, c) => _CustodiaBody(c),
  onChanged: (ref) {
    ref.invalidate(inventarioListProvider);
    ref.invalidate(dashboardProvider);
  },
);

// ------------------------------------------------------------------ datos
class _Custodia {
  final List<ItAsset> assets;
  final List<Map<String, dynamic>> history;
  const _Custodia(this.assets, this.history);
}

final _custodiaProvider = FutureProvider.autoDispose.family<_Custodia, int>((ref, id) async {
  final api = ref.watch(inventarioApiProvider);
  final assets = await api.getEmpleadoActivos(id);
  final hist = await api.getEmpleadoHistorial(id);
  return _Custodia(assets, hist);
});

String _day(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : d.toString().substring(0, 10);
}

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

void _refreshAll(WidgetRef ref, EmployeeCtx c) {
  ref.invalidate(inventarioListProvider);
  ref.invalidate(empleadosProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(_custodiaProvider(c.employee.id));
  c.reload();
}

Widget _withAssets(EmployeeCtx c, Widget Function(BuildContext, WidgetRef, List<ItAsset>) build) => Consumer(
      builder: (context, ref, _) => build(context, ref, ref.watch(_custodiaProvider(c.employee.id)).valueOrNull?.assets ?? const <ItAsset>[]),
    );

// ------------------------------------------------------------------ acciones
Future<String?> _askNotes(BuildContext context, String title, String confirm, {String? message}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(message)),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true ? ctrl.text.trim() : null;
}

Future<void> _devolver(BuildContext context, WidgetRef ref, EmployeeCtx c, ItAsset a) async {
  final notes = await _askNotes(context, 'Devolver ${a.assetTag}', 'Devolver');
  if (notes == null || !context.mounted) return;
  try {
    await ref.read(inventarioApiProvider).devolver(a.assetTag, notes);
    if (context.mounted) _refreshAll(ref, c);
  } catch (e) {
    _snack(context, 'Error: ${apiError(e)}');
  }
}

Future<void> _devolverTodos(BuildContext context, WidgetRef ref, EmployeeCtx c, List<ItAsset> assets) async {
  if (assets.isEmpty) return;
  final notes = await _askNotes(context, 'Devolver los ${assets.length} equipos', 'Devolver todos');
  if (notes == null || !context.mounted) return;
  final api = ref.read(inventarioApiProvider);
  var ok = 0, fail = 0;
  for (final a in assets) {
    try {
      await api.devolver(a.assetTag, notes);
      ok++;
    } catch (_) {
      fail++;
    }
  }
  if (!context.mounted) return;
  _refreshAll(ref, c);
  _snack(context, 'Devueltos: $ok${fail > 0 ? ' · $fail con error' : ''}');
}

Future<void> _baja(BuildContext context, WidgetRef ref, EmployeeCtx c, List<ItAsset> assets) async {
  final e = c.employee;
  final notes = await _askNotes(context, 'Dar de baja a ${e.name}', 'Dar de baja',
      message: assets.isEmpty ? 'No tiene equipos asignados. Quedará como inactivo.' : 'Se devolverán sus ${assets.length} equipo(s) y quedará como inactivo.');
  if (notes == null || !context.mounted) return;
  try {
    final n = await ref.read(inventarioApiProvider).bajaEmpleado(e.id, notes);
    if (!context.mounted) return;
    _refreshAll(ref, c);
    _snack(context, 'Baja registrada. Equipos devueltos: $n');
  } catch (err) {
    _snack(context, 'Error: ${apiError(err)}');
  }
}

Future<void> _traspasar(BuildContext context, WidgetRef ref, EmployeeCtx c, List<ItAsset> assets) async {
  final e = c.employee;
  if (assets.isEmpty) {
    _snack(context, 'No tiene equipos para traspasar.');
    return;
  }
  final emps = (await ref.read(empleadosProvider.future)).where((x) => x.active && x.id != e.id).toList();
  if (!context.mounted) return;
  Employee? to;
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text('Traspasar ${assets.length} equipo(s)'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SearchSelect<Employee>(
              label: 'Nuevo responsable', required: true, allowClear: false, value: to, options: emps,
              display: (x) => x.name,
              searchText: (x) => '${x.department ?? ''} ${x.position ?? ''} ${x.extension ?? ''}',
              subtitle: (x) => [x.position, x.department].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              onChanged: (x) => setM(() => to = x),
            ),
            const SizedBox(height: 12),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: to == null ? null : () => Navigator.pop(ctx, true), child: const Text('Traspasar')),
        ],
      ),
    ),
  );
  if (ok != true || to == null || !context.mounted) return;
  try {
    final n = await ref.read(inventarioApiProvider).traspasarEmpleado(e.id, to!.id, notes.text.trim());
    if (!context.mounted) return;
    _refreshAll(ref, c);
    _snack(context, 'Traspasados $n equipo(s) a ${to!.name}');
  } catch (err) {
    _snack(context, 'Error: ${apiError(err)}');
  }
}

Future<void> _asignar(BuildContext context, WidgetRef ref, EmployeeCtx c) async {
  final emp = c.employee;
  final all = await ref.read(inventarioListProvider.future);
  final libres = all.where((a) => !a.isDraft && (a.assignedTo == null || a.assignedTo!.trim().isEmpty)).toList();
  if (libres.isEmpty) {
    _snack(context, 'No hay equipos sin asignar.');
    return;
  }
  if (!context.mounted) return;
  final picked = <String>{};
  var q = '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
      final terms = normalizeText(q.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      final shown = libres.where((a) {
        final hay = normalizeText('${a.assetTag} ${a.category} ${a.brand} ${a.model} ${a.serialNumber ?? ''} ${a.location ?? ''}');
        return terms.every(hay.contains);
      }).take(80).toList();
      return AlertDialog(
        title: Text('Asignar equipos a ${emp.name}'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(children: [
            TextField(onChanged: (v) => setM(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Buscar equipo sin asignar…')),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final a in shown)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: picked.contains(a.assetTag),
                    onChanged: (v) => setM(() => v == true ? picked.add(a.assetTag) : picked.remove(a.assetTag)),
                    title: Text('${a.assetTag} · ${a.brand} ${a.model}'),
                    subtitle: Text('${a.category}${a.location != null ? ' · ${a.location}' : ''}'),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text('Asignar ${picked.length}')),
        ],
      );
    }),
  );
  if (ok != true || !context.mounted) return;
  final api = ref.read(inventarioApiProvider);
  var done = 0, fail = 0;
  for (final tag in picked) {
    try {
      await api.asignar(tag, emp.id, '');
      done++;
    } catch (_) {
      fail++;
    }
  }
  if (!context.mounted) return;
  _refreshAll(ref, c);
  _snack(context, 'Asignados: $done${fail > 0 ? ' · $fail con error' : ''}');
}

/// [blank] = hoja para llenar a mano con los datos del empleado y la tabla vacía.
Future<void> _acta(BuildContext context, WidgetRef ref, Employee emp, {bool blank = false}) async {
  final t = await showActaPicker(context, title: blank ? 'Hoja a mano: elige la plantilla' : 'Acta de entrega: elige la plantilla');
  if (t == null || !context.mounted) return;
  try {
    final api = ref.read(inventarioApiProvider);
    if (blank) {
      await api.descargarActaPlantilla(t.id, employeeId: emp.id, blank: true, name: 'hoja_${emp.name}');
    } else {
      await api.descargarActaEmpleado(emp.id, emp.name, templateId: t.id);
    }
  } catch (e) {
    _snack(context, 'Error: ${apiError(e)}');
  }
}

// ------------------------------------------------------------------ widgets
List<Widget> _actions(BuildContext context, EmployeeCtx c) {
  final e = c.employee;
  final bad = context.sw.bad;
  return [
    _withAssets(c, (ctx, ref, assets) => FilledButton.icon(onPressed: e.active ? () => _asignar(ctx, ref, c) : null, icon: const Icon(Icons.add, size: 18), label: const Text('Asignar equipos'))),
    _withAssets(c, (ctx, ref, assets) => OutlinedButton.icon(onPressed: assets.isEmpty ? null : () => _devolverTodos(ctx, ref, c, assets), icon: const Icon(Icons.keyboard_return, size: 18), label: const Text('Devolver todos'))),
    _withAssets(c, (ctx, ref, assets) => OutlinedButton.icon(onPressed: assets.isEmpty ? null : () => _traspasar(ctx, ref, c, assets), icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Traspasar'))),
    _withAssets(c, (ctx, ref, assets) => OutlinedButton.icon(onPressed: () => _acta(ctx, ref, e), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Acta de entrega'))),
    _withAssets(c, (ctx, ref, assets) => OutlinedButton.icon(onPressed: () => _acta(ctx, ref, e, blank: true), icon: const Icon(Icons.edit_note, size: 18), label: const Text('Hoja a mano'))),
    if (e.active)
      _withAssets(c, (ctx, ref, assets) => TextButton.icon(style: TextButton.styleFrom(foregroundColor: bad), onPressed: () => _baja(ctx, ref, c, assets), icon: const Icon(Icons.person_off_outlined, size: 18), label: const Text('Dar de baja'))),
  ];
}

class _ActaButton extends ConsumerWidget {
  final EmployeeCtx c;
  const _ActaButton(this.c);

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Acta de entrega', onPressed: () => _acta(context, ref, c.employee));
}

class _CustodiaBody extends ConsumerWidget {
  final EmployeeCtx c;
  const _CustodiaBody(this.c);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.sw;
    final async = ref.watch(_custodiaProvider(c.employee.id));
    final d = async.valueOrNull;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: async.hasError ? Text('Error: ${apiError(async.error!)}', style: TextStyle(color: colors.bad)) : const CircularProgressIndicator()),
      );
    }
    final vigentes = {
      for (final h in d.history)
        if (h['returned_at'] == null) h['asset_tag'] as String: h['assigned_at'] as String?
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      Wrap(spacing: 14, runSpacing: 14, children: [
        SizedBox(width: 200, child: KpiTile('Equipos asignados', '${d.assets.length}', icon: Icons.devices_outlined)),
        SizedBox(width: 200, child: KpiTile('Movimientos', '${d.history.length}', icon: Icons.swap_horiz, color: colors.accent2)),
      ]),
      const SizedBox(height: 24),
      SwissSection('Equipos asignados (${d.assets.length})', [
        if (d.assets.isEmpty) Text('No tiene equipos asignados.', style: TextStyle(color: colors.muted)),
        for (final a in d.assets)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await openAsset(context, a.assetTag);
              if (context.mounted) ref.invalidate(_custodiaProvider(c.employee.id));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.line))),
              child: Row(children: [
                AssetThumbnail(asset: a, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.assetTag, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${a.category} · ${a.brand} ${a.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.muted)),
                    Text('S/N ${a.serialNumber ?? 'N/A'} · desde ${_day(vigentes[a.assetTag])}', style: TextStyle(fontSize: 12, color: colors.muted)),
                  ]),
                ),
                StatusTag(status: a.status),
                IconButton(icon: const Icon(Icons.keyboard_return, size: 20), tooltip: 'Devolver', onPressed: () => _devolver(context, ref, c, a)),
              ]),
            ),
          ),
      ]),
      SwissSection('Historial de custodia', [
        if (d.history.isEmpty) Text('Sin movimientos.', style: TextStyle(color: colors.muted)),
        for (final h in d.history)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 190,
                child: Text('${_day(h['assigned_at'] as String?)} → ${h['returned_at'] == null ? 'vigente' : _day(h['returned_at'] as String?)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: h['returned_at'] == null ? colors.ok : colors.muted)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['asset_tag']}  ${h['equipo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (h['notes'] != null) Text('Entrega: ${h['notes']}', style: TextStyle(fontSize: 12, color: colors.muted)),
                  if (h['return_notes'] != null) Text('Devolución: ${h['return_notes']}', style: TextStyle(fontSize: 12, color: colors.muted)),
                  Text('Entregó ${h['delivered_by']}', style: TextStyle(fontSize: 12, color: colors.muted)),
                ]),
              ),
            ]),
          ),
      ]),
    ]);
  }
}
