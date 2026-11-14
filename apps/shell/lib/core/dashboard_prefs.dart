import 'dart:convert';
import 'package:balgres_it_inventario/balgres_it_inventario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bloques disponibles. Para añadir uno: agregar aquí (id, etiqueta) y su builder en dashboard_page.dart.
const kDashBlocks = <(String, String)>[
  ('estados', 'Estado de equipos'),
  ('stats', 'Estadísticas'),
  ('en_uso', 'Computadoras en uso'),
  ('asignaciones', 'Asignaciones por responsable'),
  ('redes', 'Red / IPs por segmento'),
  ('categorias', 'Por categoría'),
  ('modulos', 'Módulos'),
];

const kDashDefault = ['estados', 'stats', 'categorias', 'modulos'];

class DashPrefs {
  final List<String> visible;
  final Map<String, List<String>> views; // vistas guardadas: nombre -> ids
  const DashPrefs(this.visible, this.views);
}

class DashPrefsNotifier extends StateNotifier<DashPrefs> {
  DashPrefsNotifier() : super(const DashPrefs(kDashDefault, {})) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final vis = p.getStringList('dash_visible');
      final raw = p.getString('dash_views');
      final views = raw == null
          ? <String, List<String>>{}
          : (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, List<String>.from(v as List)));
      state = DashPrefs((vis == null || vis.isEmpty) ? kDashDefault : vis, views);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('dash_visible', state.visible);
      await p.setString('dash_views', jsonEncode(state.views));
    } catch (_) {}
  }

  Future<void> setVisible(List<String> ids) async {
    state = DashPrefs(ids.isEmpty ? kDashDefault : ids, state.views);
    await _persist();
  }

  Future<void> saveView(String name, List<String> ids) async {
    state = DashPrefs(state.visible, {...state.views, name: ids});
    await _persist();
  }

  Future<void> removeView(String name) async {
    state = DashPrefs(state.visible, {...state.views}..remove(name));
    await _persist();
  }
}

final dashPrefsProvider = StateNotifierProvider<DashPrefsNotifier, DashPrefs>((ref) => DashPrefsNotifier());

Future<void> showDashCustomizeDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _DashDialog());

class _DashDialog extends ConsumerStatefulWidget {
  const _DashDialog();
  @override
  ConsumerState<_DashDialog> createState() => _DashDialogState();
}

class _DashDialogState extends ConsumerState<_DashDialog> {
  late List<String> order;
  final _name = TextEditingController();

  String _label(String id) => kDashBlocks.where((b) => b.$1 == id).firstOrNull?.$2 ?? id;

  @override
  void initState() {
    super.initState();
    final known = kDashBlocks.map((b) => b.$1).toSet();
    order = ref.read(dashPrefsProvider).visible.where(known.contains).toList();
    if (order.isEmpty) order = [...kDashDefault];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final views = ref.watch(dashPrefsProvider).views;
    final available = kDashBlocks.where((b) => !order.contains(b.$1)).toList();

    return AlertDialog(
      title: const Text('Personalizar resumen'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const SectionLabel('Visibles · arrastra para ordenar'),
            const SizedBox(height: 6),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (o, n) => setState(() {
                if (n > o) n--;
                order.insert(n, order.removeAt(o));
              }),
              children: [
                for (var i = 0; i < order.length; i++)
                  ListTile(
                    key: ValueKey(order[i]),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator, color: c.muted)),
                    title: Text(_label(order[i])),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Quitar',
                      onPressed: order.length <= 1 ? null : () => setState(() => order.removeAt(i)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionLabel('Disponibles · toca para agregar'),
            const SizedBox(height: 8),
            if (available.isEmpty) Text('Ya están todos visibles', style: TextStyle(color: c.muted)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in available)
                ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(b.$2), onPressed: () => setState(() => order.add(b.$1))),
            ]),
            const SizedBox(height: 20),
            const SectionLabel('Mis vistas'),
            const SizedBox(height: 6),
            if (views.isEmpty) Text('Guarda la combinación actual, por ejemplo "Redes" o "Soporte".', style: TextStyle(color: c.muted, fontSize: 13)),
            for (final e in views.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bookmark_outline, color: c.accent),
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(e.value.map(_label).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() => order = [...e.value]),
                trailing: IconButton(icon: Icon(Icons.delete_outline, color: c.bad), tooltip: 'Borrar vista', onPressed: () => ref.read(dashPrefsProvider.notifier).removeView(e.key)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre de la vista'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final n = _name.text.trim();
                  if (n.isEmpty) return;
                  await ref.read(dashPrefsProvider.notifier).saveView(n, [...order]);
                  _name.clear();
                },
                child: const Text('Guardar'),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => order = [...kDashDefault]), child: const Text('Restablecer')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            await ref.read(dashPrefsProvider.notifier).setVisible(order);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
