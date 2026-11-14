import 'package:balgres_it_inventario/balgres_it_inventario.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';

typedef _Json = Map<String, dynamic>;

final _usersProvider = FutureProvider.autoDispose<List<_Json>>((ref) => ref.watch(authApiProvider).users());
final _rolesProvider = FutureProvider.autoDispose<List<_Json>>((ref) => ref.watch(authApiProvider).roles());
final _catalogProvider = FutureProvider.autoDispose<_Json>((ref) => ref.watch(authApiProvider).catalog());

void _snack(BuildContext c, String m) {
  if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

String _when(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? 'nunca' : d.toString().substring(0, 16);
}

class UsuariosPage extends StatelessWidget {
  const UsuariosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final mobile = MediaQuery.sizeOf(context).width < 900;
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.all(mobile ? 12 : 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Usuarios y roles', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
          const SizedBox(height: 6),
          Text('Quién entra al sistema y qué puede hacer', style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 12),
          const TabBar(tabs: [Tab(text: 'Usuarios'), Tab(text: 'Roles y permisos')]),
          const SizedBox(height: 12),
          const Expanded(child: TabBarView(children: [_UsersTab(), _RolesTab()])),
        ]),
      ),
    );
  }
}

// ====================================================================== usuarios
class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(_usersProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(onPressed: () => _userDialog(context, ref), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Nuevo usuario')),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: ${apiError(e)}')),
          data: (list) => ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final u = list[i];
              final active = u['active'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: cardDeco(context, radius: 14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text((u['full_name'] as String?) ?? u['username'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? c.ink : c.muted)),
                        if (!active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                            child: Text('Inactivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
                          ),
                      ]),
                      Text('@${u['username']} · ${u['role'] ?? 'sin rol'}', style: TextStyle(fontSize: 13, color: c.muted)),
                      Text('Último ingreso: ${_when(u['last_login'] as String?)}${u['must_change_password'] == true ? ' · debe cambiar la contraseña' : ''}', style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar', onPressed: () => _userDialog(context, ref, user: u)),
                  IconButton(icon: const Icon(Icons.key_outlined, size: 20), tooltip: 'Restablecer contraseña', onPressed: () => _resetDialog(context, ref, u)),
                ]),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

Future<void> _userDialog(BuildContext context, WidgetRef ref, {_Json? user}) async {
  List<_Json> roles;
  try {
    roles = await ref.read(_rolesProvider.future);
  } catch (e) {
    _snack(context, apiError(e));
    return;
  }
  if (!context.mounted) return;
  final username = TextEditingController(text: (user?['username'] as String?) ?? '');
  final name = TextEditingController(text: (user?['full_name'] as String?) ?? '');
  final pass = TextEditingController();
  int? roleId = (user?['role_id'] as int?) ?? roles.where((r) => r['is_system'] != true).firstOrNull?['id'] as int?;
  bool active = user?['active'] as bool? ?? true;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text(user == null ? 'Nuevo usuario' : 'Editar usuario'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: username, enabled: user == null, decoration: const InputDecoration(labelText: 'Usuario *', helperText: 'Sin espacios; no se puede cambiar después')),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo')),
              if (user == null) ...[
                const SizedBox(height: 12),
                TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña temporal *', helperText: 'Mínimo 8 caracteres. Deberá cambiarla al entrar')),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: roleId,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [for (final r in roles) DropdownMenuItem(value: r['id'] as int, child: Text(r['name'] as String))],
                onChanged: (v) => setM(() => roleId = v),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: active, onChanged: (v) => setM(() => active = v)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (roleId == null || (user == null && (username.text.trim().isEmpty || pass.text.isEmpty))) return;
              try {
                final api = ref.read(authApiProvider);
                if (user == null) {
                  await api.crearUsuario({'username': username.text.trim(), 'full_name': name.text.trim(), 'password': pass.text, 'role_id': roleId, 'active': active});
                } else {
                  await api.actualizarUsuario(user['id'] as int, {'full_name': name.text.trim(), 'role_id': roleId, 'active': active});
                }
                ref.invalidate(_usersProvider);
                ref.invalidate(_rolesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                _snack(ctx, apiError(e));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _resetDialog(BuildContext context, WidgetRef ref, _Json user) async {
  final pass = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Restablecer contraseña de ${user['username']}'),
      content: SizedBox(
        width: 400,
        child: TextField(controller: pass, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Contraseña temporal', helperText: 'Se cerrarán sus sesiones y deberá cambiarla al entrar')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            try {
              await ref.read(authApiProvider).resetearClave(user['id'] as int, pass.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _snack(context, 'Contraseña restablecida');
            } catch (e) {
              _snack(ctx, apiError(e));
            }
          },
          child: const Text('Restablecer'),
        ),
      ],
    ),
  );
}

// ====================================================================== roles
String _permSummary(List perms, _Json? cat) {
  if (perms.contains('*')) return 'Acceso total';
  final labels = {for (final m in (cat?['modules'] as List? ?? const [])) (m as Map)['id']: m['label']};
  final by = <String, List<String>>{};
  for (final p in perms) {
    final parts = p.toString().split('.');
    if (parts.length == 2) by.putIfAbsent(parts[0], () => []).add(parts[1]);
  }
  if (by.isEmpty) return 'Sin permisos';
  return by.entries.map((e) => '${labels[e.key] ?? e.key}: ${e.value.join(', ')}').join('  ·  ');
}

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(_rolesProvider);
    final cat = ref.watch(_catalogProvider).valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(onPressed: () => _roleDialog(context, ref), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo rol')),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: ${apiError(e)}')),
          data: (list) => ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final system = r['is_system'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: cardDeco(context, radius: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2, right: 12), child: Icon(system ? Icons.lock_outline : Icons.shield_outlined, color: c.accent)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['name']}  ·  ${r['users']} usuario(s)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (((r['description'] as String?) ?? '').isNotEmpty) Text(r['description'] as String, style: TextStyle(fontSize: 13, color: c.muted)),
                      const SizedBox(height: 4),
                      Text(_permSummary(r['permissions'] as List? ?? const [], cat), style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
                  if (!system) ...[
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar', onPressed: () => _roleDialog(context, ref, role: r)),
                    IconButton(icon: Icon(Icons.delete_outline, size: 20, color: c.bad), tooltip: 'Eliminar', onPressed: () => _deleteRole(context, ref, r)),
                  ],
                ]),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

Future<void> _deleteRole(BuildContext context, WidgetRef ref, _Json role) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar rol'),
      content: Text('¿Eliminar el rol "${role['name']}"? Solo se puede si ningún usuario lo tiene.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(authApiProvider).eliminarRol(role['id'] as int);
    ref.invalidate(_rolesProvider);
  } catch (e) {
    _snack(context, apiError(e));
  }
}

Future<void> _roleDialog(BuildContext context, WidgetRef ref, {_Json? role}) async {
  _Json cat;
  try {
    cat = await ref.read(_catalogProvider.future);
  } catch (e) {
    _snack(context, apiError(e));
    return;
  }
  if (!context.mounted) return;
  final mods = [for (final m in cat['modules'] as List) _Json.from(m as Map)];
  final acts = [for (final a in cat['actions'] as List) _Json.from(a as Map)];
  final name = TextEditingController(text: (role?['name'] as String?) ?? '');
  final desc = TextEditingController(text: (role?['description'] as String?) ?? '');
  final perms = <String>{for (final p in (role?['permissions'] as List? ?? const [])) p.toString()};

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
      void toggle(String m, String a, bool on) {
        setM(() {
          if (on) {
            perms.add('$m.$a');
            if (a != 'ver') perms.add('$m.ver'); // editar/eliminar sin ver no sirve
          } else {
            perms.remove('$m.$a');
            if (a == 'ver') perms.removeWhere((p) => p.startsWith('$m.'));
          }
        });
      }

      return AlertDialog(
        title: Text(role == null ? 'Nuevo rol' : 'Editar rol'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del rol *')),
              const SizedBox(height: 12),
              TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción')),
              const SizedBox(height: 20),
              const SectionLabel('Permisos por módulo'),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {0: FlexColumnWidth(2)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(children: [
                    const SizedBox.shrink(),
                    for (final a in acts) Padding(padding: const EdgeInsets.only(bottom: 4), child: Center(child: Text(a['label'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))),
                  ]),
                  for (final m in mods)
                    TableRow(children: [
                      Text(m['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      for (final a in acts)
                        Center(child: Checkbox(value: perms.contains('${m['id']}.${a['id']}'), onChanged: (v) => toggle(m['id'] as String, a['id'] as String, v == true))),
                    ]),
                ],
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final body = {'name': name.text.trim(), 'description': desc.text.trim(), 'permissions': perms.toList()};
              try {
                final api = ref.read(authApiProvider);
                if (role == null) {
                  await api.crearRol(body);
                } else {
                  await api.actualizarRol(role['id'] as int, body);
                }
                ref.invalidate(_rolesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                _snack(ctx, apiError(e));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    }),
  );
}
