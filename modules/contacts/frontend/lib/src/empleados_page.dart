import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'extensions.dart';
import 'models.dart';
import 'providers.dart';

String _initials(String n) {
  final p = n.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

List<String> _uniq(Iterable<String?> v) {
  final s = <String>{for (final x in v) if ((x ?? '').trim().isNotEmpty) x!.trim()}.toList()..sort();
  return s;
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
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(_initials(name), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Mini(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: c.muted),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}

/// Alta / edición de empleado.
Future<void> showEmployeeDialog(BuildContext context, WidgetRef ref, {Employee? emp}) async {
  final name = TextEditingController(text: emp?.name ?? '');
  final code = TextEditingController(text: emp?.employeeCode ?? '');
  final position = TextEditingController(text: emp?.position ?? '');
  final dept = TextEditingController(text: emp?.department ?? '');
  final email = TextEditingController(text: emp?.email ?? '');
  final phone = TextEditingController(text: emp?.phone ?? '');
  final ext = TextEditingController(text: emp?.extension ?? '');
  final notes = TextEditingController(text: emp?.notes ?? '');
  bool active = emp?.active ?? true;

  var locs = const <Location>[];
  try {
    locs = await ref.read(contactLocationsProvider.future);
  } catch (_) {}
  Location? loc = locs.where((l) => l.id == emp?.locationId).firstOrNull;
  final all = ref.read(empleadosProvider).valueOrNull ?? const <Employee>[];
  final depts = _uniq(all.map((e) => e.department));
  final positions = _uniq(all.map((e) => e.position));
  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text(emp == null ? 'Nuevo empleado' : 'Editar empleado'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo *')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: code, decoration: const InputDecoration(labelText: 'Código / ID'))),
                const SizedBox(width: 12),
                Expanded(child: SuggestField(controller: position, label: 'Cargo', suggestions: () => positions)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: SuggestField(controller: dept, label: 'Departamento', suggestions: () => depts)),
                const SizedBox(width: 12),
                Expanded(
                  child: SearchSelect<Location>(
                    label: 'Sede / ubicación', value: loc, options: locs, display: (l) => l.fullName, subtitle: (l) => l.kind ?? '',
                    onChanged: (l) => setM(() => loc = l),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined, size: 18)))),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: TextField(controller: ext, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Extensión', prefixIcon: Icon(Icons.dialpad, size: 18)))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: active, onChanged: (v) => setM(() => active = v)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final body = {
                'name': name.text.trim(), 'employee_code': code.text.trim(), 'position': position.text.trim(),
                'department': dept.text.trim(), 'email': email.text.trim(), 'phone': phone.text.trim(),
                'extension': ext.text.trim(), 'location_id': loc?.id, 'notes': notes.text.trim(), 'active': active,
              };
              try {
                final api = ref.read(contactsApiProvider);
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
enum _Status { active, inactive, all }

enum _Assets { all, withAssets, noAssets }

class EmpleadosPage extends ConsumerStatefulWidget {
  const EmpleadosPage({super.key});
  @override
  ConsumerState<EmpleadosPage> createState() => _EmpleadosPageState();
}

class _EmpleadosPageState extends ConsumerState<EmpleadosPage> {
  String _q = '';
  String? _dept;
  _Status _status = _Status.active;
  _Assets _assets = _Assets.all;
  bool _byAssets = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

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
    final entries = [for (final x in ref.watch(employeeExtensionsProvider)) ...x.menu];

    final depts = _uniq(all.map((e) => e.department));
    final terms = normalizeText(_q.trim());
    final list = all.where((e) {
      if (_status == _Status.active && !e.active) return false;
      if (_status == _Status.inactive && e.active) return false;
      if (_assets == _Assets.withAssets && e.assetCount == 0) return false;
      if (_assets == _Assets.noAssets && e.assetCount > 0) return false;
      if (_dept != null && e.department?.trim() != _dept) return false;
      if (terms.isEmpty) return true;
      final hay = normalizeText([e.name, e.email, e.department, e.position, e.phone, e.extension, e.employeeCode, e.location].whereType<String>().join(' '));
      return terms.split(RegExp(r'\s+')).every(hay.contains);
    }).toList()
      ..sort((a, b) => _byAssets ? b.assetCount.compareTo(a.assetCount) : normalizeText(a.name).compareTo(normalizeText(b.name)));

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
              Text('Directorio y custodia de equipos', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) async {
              if (v == 'excel') {
                try {
                  await ref.read(contactsApiProvider).descargarEmpleadosExcel();
                } catch (e) {
                  _snack('Error: ${apiError(e)}');
                }
              } else {
                await entries[int.parse(v)].onSelected(context, ref);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              for (var i = 0; i < entries.length; i++) PopupMenuItem<String>(value: '$i', child: Text(entries[i].label)),
              if (entries.isNotEmpty) const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'excel', child: Text('Exportar a Excel')),
            ],
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
          decoration: const InputDecoration(hintText: 'Buscar por nombre, cargo, teléfono, extensión, correo, departamento…', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in _Status.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(const {_Status.active: 'Activos', _Status.inactive: 'Inactivos', _Status.all: 'Todos'}[s]!), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
              ),
            const SizedBox(width: 8),
            for (final a in _Assets.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(const {_Assets.all: 'Con y sin equipos', _Assets.withAssets: 'Con equipos', _Assets.noAssets: 'Sin equipos'}[a]!), selected: _assets == a, onSelected: (_) => setState(() => _assets = a)),
              ),
            const SizedBox(width: 8),
            for (final d in depts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(d), selected: _dept == d, onSelected: (v) => setState(() => _dept = v ? d : null)),
              ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Ordenar por equipos'), selected: _byAssets, onSelected: (v) => setState(() => _byAssets = v)),
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
                            final sub = [e.position, e.department].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
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
                                          if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
                                          const SizedBox(height: 4),
                                          Wrap(spacing: 14, runSpacing: 2, children: [
                                            if ((e.phone ?? '').isNotEmpty) _Mini(Icons.phone_outlined, e.phone!),
                                            if ((e.extension ?? '').isNotEmpty) _Mini(Icons.dialpad, 'Ext. ${e.extension}'),
                                            if ((e.email ?? '').isNotEmpty) _Mini(Icons.mail_outline, e.email!),
                                            if ((e.location ?? '').isNotEmpty) _Mini(Icons.place_outlined, e.location!),
                                            if (!e.active) _Mini(Icons.block, 'Inactivo'),
                                          ]),
                                        ]),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: (e.assetCount > 0 ? c.accent : c.muted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${e.assetCount} equipo${e.assetCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: e.assetCount > 0 ? c.accent : c.muted)),
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final emp = await ref.read(contactsApiProvider).getEmpleado(widget.employeeId);
      if (mounted) setState(() => _emp = emp);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editar() async {
    await showEmployeeDialog(context, ref, emp: _emp);
    if (!mounted) return;
    ref.invalidate(empleadosProvider);
    for (final x in ref.read(employeeExtensionsProvider)) {
      x.onChanged?.call(ref);
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final exts = ref.watch(employeeExtensionsProvider);
    final emp = _emp;
    final ctx = emp == null ? null : EmployeeCtx(emp, () => _load(silent: true));
    return Scaffold(
      appBar: AppBar(
        title: Text(emp?.name ?? 'Empleado'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: emp == null ? null : _editar),
          if (ctx != null) for (final x in exts) ...?x.appBarActions?.call(context, ctx),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || ctx == null
              ? Center(child: Text(_error ?? 'Empleado no encontrado'))
              : ListView(padding: EdgeInsets.all(wide ? 32 : 16), children: [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _content(c, ctx, exts))),
                ]),
    );
  }

  Widget _contactChip(SwissColors c, IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        _snack('Copiado: $value');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: c.accent),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10, color: c.muted, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  Widget _content(SwissColors c, EmployeeCtx ctx, List<EmployeeExtension> exts) {
    final e = ctx.employee;
    final sub = [e.position, e.department].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

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
                Text(sub.isEmpty ? 'Sin cargo ni departamento' : sub, style: TextStyle(fontSize: 14, color: c.muted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: (e.active ? c.ok : c.muted).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                  child: Text(e.active ? 'Activo' : 'Inactivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: e.active ? c.ok : c.muted)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _contactChip(c, Icons.phone_outlined, 'TELÉFONO', e.phone),
            _contactChip(c, Icons.dialpad, 'EXTENSIÓN', e.extension),
            _contactChip(c, Icons.mail_outline, 'CORREO', e.email),
            _contactChip(c, Icons.place_outlined, 'UBICACIÓN', e.location),
            _contactChip(c, Icons.badge_outlined, 'CÓDIGO', e.employeeCode),
          ]),
          if ((e.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.notes!, style: TextStyle(fontSize: 13, color: c.muted)),
          ],
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final x in exts) ...?x.actions?.call(context, ctx),
            OutlinedButton.icon(onPressed: _editar, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar datos')),
          ]),
        ]),
      ),
      for (final x in exts)
        if (x.body != null) x.body!(context, ctx),
    ]);
  }
}
