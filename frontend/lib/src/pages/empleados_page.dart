import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/filters.dart';
import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';

String _initials(String n) {
  final p = n.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

String _day(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : d.toString().substring(0, 10);
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool active;
  const _Avatar(this.name, {this.size = 44, this.active = true});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final bg = active ? c.accent : c.edge;
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(_initials(name), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

/// Alta / edición de empleado.
Future<void> showEmployeeDialog(BuildContext context, WidgetRef ref, {Employee? emp}) async {
  final name = TextEditingController(text: emp?.name ?? '');
  final email = TextEditingController(text: emp?.email ?? '');
  final dept = TextEditingController(text: emp?.department ?? '');
  bool active = emp?.active ?? true;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text(emp == null ? 'Nuevo empleado' : 'Editar empleado'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
              const SizedBox(height: 12),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Correo')),
              const SizedBox(height: 12),
              TextField(controller: dept, decoration: const InputDecoration(labelText: 'Departamento')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: active, onChanged: (v) => setM(() => active = v)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final body = {'name': name.text.trim(), 'email': email.text.trim(), 'department': dept.text.trim(), 'active': active};
              try {
                final api = ref.read(inventarioApiProvider);
                if (emp == null) {
                  await api.crearEmpleado(body);
                } else {
                  await api.actualizarEmpleado(emp.id, body);
                }
                ref.invalidate(empleadosProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiError(e))));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

// ====================================================================== lista
class EmpleadosPage extends ConsumerStatefulWidget {
  const EmpleadosPage({super.key});
  @override
  ConsumerState<EmpleadosPage> createState() => _EmpleadosPageState();
}

class _EmpleadosPageState extends ConsumerState<EmpleadosPage> {
  String _q = '';
  String? _dept;
  bool _onlyActive = true;

  Future<void> _open(Employee e) async {
    await context.push('/empleados/${e.id}');
    ref.invalidate(empleadosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final async = ref.watch(empleadosProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final all = async.valueOrNull ?? const <Employee>[];

    final depts = <String>{for (final e in all) if ((e.department ?? '').trim().isNotEmpty) e.department!.trim()}.toList()..sort();
    final terms = normalizeText(_q.trim());
    final list = all.where((e) {
      if (_onlyActive && !e.active) return false;
      if (_dept != null && e.department?.trim() != _dept) return false;
      if (terms.isEmpty) return true;
      return normalizeText('${e.name} ${e.email ?? ''} ${e.department ?? ''}').contains(terms);
    }).toList();

    final activos = all.where((e) => e.active).length;
    final conEquipos = all.where((e) => e.assetCount > 0).length;
    final equipos = all.fold<int>(0, (s, e) => s + e.assetCount);

    return Padding(
      padding: EdgeInsets.all(mobile ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Empleados', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 6),
              Text('Custodios de los activos de TI', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(empleadosProvider)),
          const SizedBox(width: 4),
          FilledButton.icon(onPressed: () => showEmployeeDialog(context, ref), icon: const Icon(Icons.person_add_alt, size: 18), label: Text(mobile ? 'Nuevo' : 'Nuevo empleado')),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          SizedBox(width: 190, child: KpiTile('Empleados activos', '$activos', icon: Icons.groups_outlined)),
          SizedBox(width: 190, child: KpiTile('Con equipos', '$conEquipos', icon: Icons.devices_outlined, color: c.accent2)),
          SizedBox(width: 190, child: KpiTile('Equipos asignados', '$equipos', icon: Icons.inventory_2_outlined, color: c.ok)),
        ]),
        const SizedBox(height: 18),
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(hintText: 'Buscar por nombre, correo o departamento…', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            FilterChip(label: const Text('Solo activos'), selected: _onlyActive, onSelected: (v) => setState(() => _onlyActive = v)),
            const SizedBox(width: 8),
            for (final d in depts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(d), selected: _dept == d, onSelected: (v) => setState(() => _dept = v ? d : null)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: async.isLoading && all.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError && all.isEmpty
                  ? Center(child: Text('Error: ${apiError(async.error!)}'))
                  : list.isEmpty
                      ? EmptyState(
                          icon: Icons.groups_outlined,
                          title: all.isEmpty ? 'Aún no hay empleados' : 'Sin resultados',
                          subtitle: all.isEmpty ? 'Crea el primero o impórtalos desde los activos.' : 'Prueba con otro nombre o quita los filtros.',
                          action: 'Nuevo empleado',
                          onAction: () => showEmployeeDialog(context, ref),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final e = list[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: cardDeco(context, radius: 14),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _open(e),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(children: [
                                      _Avatar(e.name, active: e.active),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(e.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: e.active ? c.ink : c.muted)),
                                          const SizedBox(height: 2),
                                          Text([e.department, e.email, if (!e.active) 'Inactivo'].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                                        ]),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: (e.assetCount > 0 ? c.accent : c.muted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${e.assetCount} equipo${e.assetCount == 1 ? '' : 's'}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: e.assetCount > 0 ? c.accent : c.muted)),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(Icons.chevron_right, color: c.edge),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

// ====================================================================== ficha
class EmpleadoDetailPage extends ConsumerStatefulWidget {
  final int employeeId;
  const EmpleadoDetailPage({super.key, required this.employeeId});
  @override
  ConsumerState<EmpleadoDetailPage> createState() => _EmpleadoDetailPageState();
}

class _EmpleadoDetailPageState extends ConsumerState<EmpleadoDetailPage> {
  Employee? _emp;
  List<ItAsset> _assets = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshAll() {
    ref.invalidate(inventarioListProvider);
    ref.invalidate(empleadosProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(inventarioApiProvider);
      final emp = await api.getEmpleado(widget.employeeId);
      final assets = await api.getEmpleadoActivos(widget.employeeId);
      final hist = await api.getEmpleadoHistorial(widget.employeeId);
      if (mounted) setState(() { _emp = emp; _assets = assets; _history = hist; });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askNotes(String title, String confirm) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 400, child: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Notas / estado (opcional)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
        ],
      ),
    );
    return ok == true ? ctrl.text.trim() : null;
  }

  Future<void> _devolver(ItAsset a) async {
    final notes = await _askNotes('Devolver ${a.assetTag}', 'Devolver');
    if (notes == null) return;
    try {
      await ref.read(inventarioApiProvider).devolver(a.assetTag, notes);
      _refreshAll();
      await _load(silent: true);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _devolverTodos() async {
    if (_assets.isEmpty) return;
    final notes = await _askNotes('Devolver los ${_assets.length} equipos', 'Devolver todos');
    if (notes == null) return;
    final api = ref.read(inventarioApiProvider);
    var ok = 0, fail = 0;
    for (final a in _assets) {
      try {
        await api.devolver(a.assetTag, notes);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    _refreshAll();
    await _load(silent: true);
    _snack('Devueltos: $ok${fail > 0 ? ' · $fail con error' : ''}');
  }

  Future<void> _asignar() async {
    final emp = _emp!;
    final all = await ref.read(inventarioListProvider.future);
    final libres = all.where((a) => !a.isDraft && (a.assignedTo == null || a.assignedTo!.trim().isEmpty)).toList();
    if (libres.isEmpty) {
      _snack('No hay equipos sin asignar.');
      return;
    }
    if (!mounted) return;
    final picked = <String>{};
    var q = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        final t = normalizeText(q.trim());
        final shown = libres
            .where((a) => t.isEmpty || normalizeText('${a.assetTag} ${a.category} ${a.brand} ${a.model} ${a.serialNumber ?? ''}').contains(t))
            .take(80)
            .toList();
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
    if (ok != true) return;
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
    _refreshAll();
    await _load(silent: true);
    _snack('Asignados: $done${fail > 0 ? ' · $fail con error' : ''}');
  }

  Future<void> _acta() async {
    try {
      await ref.read(inventarioApiProvider).descargarActaEmpleado(_emp!.id, _emp!.name);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _editar() async {
    await showEmployeeDialog(context, ref, emp: _emp);
    _refreshAll();
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text(_emp?.name ?? 'Empleado'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _emp == null ? null : _editar),
          IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Acta de entrega (PDF)', onPressed: _emp == null ? null : _acta),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: EdgeInsets.all(wide ? 32 : 16), children: [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _content(c))),
                ]),
    );
  }

  Widget _content(SwissColors c) {
    final e = _emp!;
    final valor = _assets.fold<double>(0, (s, a) => s + (a.cost ?? 0));
    final vigentes = {
      for (final h in _history)
        if (h['returned_at'] == null) h['asset_tag'] as String: h['assigned_at'] as String?
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: cardDeco(context, radius: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Avatar(e.name, size: 72, active: e.active),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                const SizedBox(height: 4),
                Text([e.department, e.email].whereType<String>().where((s) => s.isNotEmpty).join(' · ').ifEmpty('Sin departamento ni correo'), style: TextStyle(fontSize: 14, color: c.muted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: (e.active ? c.ok : c.muted).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                  child: Text(e.active ? 'Activo' : 'Inactivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: e.active ? c.ok : c.muted)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(onPressed: e.active ? _asignar : null, icon: const Icon(Icons.add, size: 18), label: const Text('Asignar equipos')),
            OutlinedButton.icon(onPressed: _assets.isEmpty ? null : _devolverTodos, icon: const Icon(Icons.keyboard_return, size: 18), label: const Text('Devolver todos')),
            OutlinedButton.icon(onPressed: _acta, icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Acta de entrega')),
            OutlinedButton.icon(onPressed: _editar, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar datos')),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      Wrap(spacing: 14, runSpacing: 14, children: [
        SizedBox(width: 200, child: KpiTile('Equipos asignados', '${_assets.length}', icon: Icons.devices_outlined)),
        SizedBox(width: 200, child: KpiTile('Valor en custodia', '\$${valor.toStringAsFixed(0)}', icon: Icons.attach_money, color: c.ok)),
        SizedBox(width: 200, child: KpiTile('Movimientos', '${_history.length}', icon: Icons.swap_horiz, color: c.accent2)),
      ]),
      const SizedBox(height: 24),
      SwissSection('Equipos asignados (${_assets.length})', [
        if (_assets.isEmpty) Text('No tiene equipos asignados.', style: TextStyle(color: c.muted)),
        for (final a in _assets)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await openAsset(context, a.assetTag);
              _load(silent: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [
                AssetThumbnail(asset: a, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.assetTag, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${a.category} · ${a.brand} ${a.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                    Text('S/N ${a.serialNumber ?? 'N/A'} · desde ${_day(vigentes[a.assetTag])}', style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ),
                StatusTag(status: a.status),
                IconButton(icon: const Icon(Icons.keyboard_return, size: 20), tooltip: 'Devolver', onPressed: () => _devolver(a)),
              ]),
            ),
          ),
      ]),
      SwissSection('Historial de custodia', [
        if (_history.isEmpty) Text('Sin movimientos.', style: TextStyle(color: c.muted)),
        for (final h in _history)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 190,
                child: Text('${_day(h['assigned_at'] as String?)} → ${h['returned_at'] == null ? 'vigente' : _day(h['returned_at'] as String?)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: h['returned_at'] == null ? c.ok : c.muted)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['asset_tag']}  ${h['equipo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (h['notes'] != null) Text('Entrega: ${h['notes']}', style: TextStyle(fontSize: 12, color: c.muted)),
                  if (h['return_notes'] != null) Text('Devolución: ${h['return_notes']}', style: TextStyle(fontSize: 12, color: c.muted)),
                  Text('Entregó ${h['delivered_by']}', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ]),
          ),
      ]),
    ]);
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
