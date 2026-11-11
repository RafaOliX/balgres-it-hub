import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/table_prefs.dart';
import '../ui/swiss.dart';

Future<void> showColumnsDialog(BuildContext context, List<ColumnDef> all) =>
    showDialog(context: context, builder: (_) => _ColumnsDialog(all: all));

class _ColumnsDialog extends ConsumerStatefulWidget {
  final List<ColumnDef> all;
  const _ColumnsDialog({required this.all});
  @override
  ConsumerState<_ColumnsDialog> createState() => _ColumnsDialogState();
}

class _ColumnsDialogState extends ConsumerState<_ColumnsDialog> {
  late List<String> order;
  final _name = TextEditingController();

  Map<String, ColumnDef> get _byId => {for (final c in widget.all) c.id: c};

  @override
  void initState() {
    super.initState();
    order = ref.read(columnsProvider).visible.where(_byId.containsKey).toList();
    if (order.isEmpty) order = [...kDefaultColumns];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final byId = _byId;
    final saved = ref.watch(columnsProvider).saved;
    final available = widget.all.where((d) => !order.contains(d.id)).toList();

    return AlertDialog(
      title: const Text('Columnas de la tabla'),
      content: SizedBox(
        width: 560,
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
                    title: Text(byId[order[i]]?.label ?? order[i]),
                    subtitle: (byId[order[i]]?.isSpec ?? false) ? const Text('Dato técnico', style: TextStyle(fontSize: 11)) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Quitar',
                      onPressed: order.length <= 1 ? null : () => setState(() => order.removeAt(i)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionLabel('Disponibles · toca para agregar'),
            const SizedBox(height: 8),
            if (available.isEmpty) Text('Ya están todas visibles', style: TextStyle(color: c.muted)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in available)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(d.isSpec ? '${d.label} · técnico' : d.label),
                  onPressed: () => setState(() => order.add(d.id)),
                ),
            ]),
            const SizedBox(height: 22),
            const SectionLabel('Mis combinaciones favoritas'),
            const SizedBox(height: 6),
            if (saved.isEmpty) Text('Guarda la combinación actual con un nombre, por ejemplo "Redes" o "Compras".', style: TextStyle(color: c.muted, fontSize: 13)),
            for (final s in saved)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bookmark_outline, color: c.accent),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(s.ids.map((id) => byId[id]?.label ?? id).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() => order = s.ids.where(byId.containsKey).toList()),
                trailing: IconButton(icon: Icon(Icons.delete_outline, color: c.bad), tooltip: 'Borrar favorito', onPressed: () => ref.read(columnsProvider.notifier).removeSaved(s.name)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre del favorito'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final n = _name.text.trim();
                  if (n.isEmpty) return;
                  await ref.read(columnsProvider.notifier).saveAs(n, [...order]);
                  _name.clear();
                },
                child: const Text('Guardar'),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => order = [...kDefaultColumns]), child: const Text('Restablecer')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            await ref.read(columnsProvider.notifier).setVisible(order);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
