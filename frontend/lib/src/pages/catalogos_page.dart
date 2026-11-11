import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class CatalogosPage extends StatelessWidget {
  const CatalogosPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Empleados y ubicaciones'), elevation: 0.5,
            bottom: const TabBar(tabs: [Tab(text: 'Empleados'), Tab(text: 'Ubicaciones')]),
          ),
          body: const TabBarView(children: [_EmpleadosTab(), _UbicacionesTab()]),
        ),
      );
}

// ------------------------------------------------------------------ empleados
class _EmpleadosTab extends ConsumerWidget {
  const _EmpleadosTab();

  Future<void> _dialog(BuildContext context, WidgetRef ref, {Employee? emp}) async {
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
                SwitchListTile(title: const Text('Activo'), value: active, onChanged: (v) => setM(() => active = v)),
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
                  if (ctx.mounted) _snack(ctx, apiError(e));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(empleadosProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          FilledButton.icon(onPressed: () => _dialog(context, ref), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Nuevo')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Importar desde activos'),
            onPressed: () async {
              try {
                final r = await ref.read(inventarioApiProvider).importarEmpleados();
                ref.invalidate(empleadosProvider);
                if (context.mounted) _snack(context, '${r['empleados_creados']} empleados creados, ${r['activos_vinculados']} activos vinculados');
              } catch (e) {
                if (context.mounted) _snack(context, apiError(e));
              }
            },
          ),
        ]),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => list.isEmpty
              ? const Center(child: Text('Sin empleados'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = list[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase())),
                      title: Text(e.name, style: TextStyle(color: e.active ? null : Colors.grey)),
                      subtitle: Text([e.department, e.email, if (!e.active) 'Inactivo'].whereType<String>().join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _dialog(context, ref, emp: e)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            try {
                              await ref.read(inventarioApiProvider).eliminarEmpleado(e.id);
                              ref.invalidate(empleadosProvider);
                            } catch (err) {
                              if (context.mounted) _snack(context, apiError(err));
                            }
                          },
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ ubicaciones
class _UbicacionesTab extends ConsumerWidget {
  const _UbicacionesTab();

  Future<void> _dialog(BuildContext context, WidgetRef ref, List<Location> all, {Location? loc}) async {
    final name = TextEditingController(text: loc?.name ?? '');
    String? kind = loc?.kind;
    int? parentId = loc?.parentId;
    const kinds = ['Sede', 'Área', 'Oficina', 'Bodega'];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: Text(loc == null ? 'Nueva ubicación' : 'Editar ubicación'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: kind, decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [const DropdownMenuItem<String?>(value: null, child: Text('—')), ...kinds.map((k) => DropdownMenuItem<String?>(value: k, child: Text(k)))],
                  onChanged: (v) => setM(() => kind = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: all.any((l) => l.id == parentId) ? parentId : null, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Dentro de (opcional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Ninguna (nivel principal)')),
                    ...all.where((l) => l.id != loc?.id).map((l) => DropdownMenuItem<int?>(value: l.id, child: Text(l.fullName, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setM(() => parentId = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final body = {'name': name.text.trim(), 'kind': kind, 'parent_id': parentId};
                try {
                  final api = ref.read(inventarioApiProvider);
                  if (loc == null) {
                    await api.crearUbicacion(body);
                  } else {
                    await api.actualizarUbicacion(loc.id, body);
                  }
                  ref.invalidate(ubicacionesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) _snack(ctx, apiError(e));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ubicacionesProvider);
    final all = async.valueOrNull ?? const <Location>[];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          FilledButton.icon(onPressed: () => _dialog(context, ref, all), icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Nueva')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Unificar desde activos'),
            onPressed: () async {
              try {
                final r = await ref.read(inventarioApiProvider).importarUbicaciones();
                ref.invalidate(ubicacionesProvider);
                if (context.mounted) _snack(context, '${r['ubicaciones_creadas']} ubicaciones creadas, ${r['activos_vinculados']} activos vinculados');
              } catch (e) {
                if (context.mounted) _snack(context, apiError(e));
              }
            },
          ),
        ]),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => list.isEmpty
              ? const Center(child: Text('Sin ubicaciones'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = list[i];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined, color: Colors.blue),
                      title: Text(l.fullName),
                      subtitle: l.kind == null ? null : Text(l.kind!),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _dialog(context, ref, list, loc: l)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            try {
                              await ref.read(inventarioApiProvider).eliminarUbicacion(l.id);
                              ref.invalidate(ubicacionesProvider);
                            } catch (err) {
                              if (context.mounted) _snack(context, apiError(err));
                            }
                          },
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
