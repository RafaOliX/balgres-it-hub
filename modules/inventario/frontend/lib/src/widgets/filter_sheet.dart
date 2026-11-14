import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/filters.dart';
import '../data/providers.dart';
import '../data/table_prefs.dart';
import '../models/category.dart';
import '../models/it_asset.dart';

Future<void> showFiltersSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => const _FiltersSheet(),
    );

Future<void> showSavedViewsDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _SavedViewsDialog());

const _statuses = ['Operativo', 'En Revisión', 'Retirado'];

Widget _section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        child,
      ]),
    );

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(inventoryFilterProvider);
    final items = ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? const <Category>[];
    void set(InventoryFilter n) => ref.read(inventoryFilterProvider.notifier).state = n;

    final locations = <String>{for (final a in items) a.location ?? kNoLocation}.toList()..sort();
    final count = applyFilter(items, f).length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                _section(
                  'Estado',
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final s in _statuses)
                      FilterChip(
                        label: Text(s),
                        selected: !f.showDrafts && f.statuses.contains(s),
                        onSelected: (v) {
                          final next = {...f.statuses};
                          v ? next.add(s) : next.remove(s);
                          set(f.copyWith(statuses: next, showDrafts: false));
                        },
                      ),
                    FilterChip(
                      label: const Text('Borradores'),
                      selected: f.showDrafts,
                      onSelected: (v) => set(f.copyWith(showDrafts: v, statuses: <String>{})),
                    ),
                  ]),
                ),
                if (cats.isNotEmpty)
                  _section(
                    'Categoría',
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final c in cats)
                        FilterChip(
                          label: Text(c.name),
                          selected: f.categoryIds.contains(c.id),
                          onSelected: (v) {
                            final next = {...f.categoryIds};
                            v ? next.add(c.id) : next.remove(c.id);
                            set(f.copyWith(categoryIds: next));
                          },
                        ),
                    ]),
                  ),
                if (locations.isNotEmpty)
                  _section(
                    'Ubicación',
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final l in locations)
                        FilterChip(
                          label: Text(l),
                          selected: f.locations.contains(l),
                          onSelected: (v) {
                            final next = {...f.locations};
                            v ? next.add(l) : next.remove(l);
                            set(f.copyWith(locations: next));
                          },
                        ),
                    ]),
                  ),
                _section(
                  'Responsable',
                  Wrap(spacing: 8, children: [
                    for (final e in assignLabels.entries)
                      ChoiceChip(label: Text(e.value), selected: f.assign == e.key, onSelected: (_) => set(f.copyWith(assign: e.key))),
                  ]),
                ),
                _section(
                  'Ordenar por',
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in sortLabels.entries)
                      ChoiceChip(label: Text(e.value), selected: f.sortCol == null && f.sort == e.key, onSelected: (_) => set(f.copyWith(sort: e.key, clearSortCol: true))),
                  ]),
                ),
                _section(
                  'Ordenar por columna (toca otra vez para invertir)',
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final d in allColumns(items))
                      ChoiceChip(
                        label: Text('${d.label}${f.sortCol == d.id ? (f.sortAsc ? ' ↑' : ' ↓') : ''}'),
                        selected: f.sortCol == d.id,
                        onSelected: (_) => set(nextColumnSort(f, d.id)),
                      ),
                  ]),
                ),
                _section(
                  'Agrupar por',
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(label: const Text('Sin agrupar'), selected: f.groupBy == null, onSelected: (_) => set(f.copyWith(clearGroupBy: true))),
                    for (final e in groupLabels.entries)
                      ChoiceChip(label: Text(e.value), selected: f.groupBy == e.key, onSelected: (_) => set(f.copyWith(groupBy: e.key))),
                  ]),
                ),
              ]),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              TextButton(onPressed: () => set(InventoryFilter(query: f.query)), child: const Text('Limpiar')),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text('Ver $count resultado${count == 1 ? '' : 's'}')),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SavedViewsDialog extends ConsumerStatefulWidget {
  const _SavedViewsDialog();
  @override
  ConsumerState<_SavedViewsDialog> createState() => _SavedViewsDialogState();
}

class _SavedViewsDialogState extends ConsumerState<_SavedViewsDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedFiltersProvider);
    final f = ref.watch(inventoryFilterProvider);

    return AlertDialog(
      title: const Text('Vistas guardadas'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Actual: ${f.summary}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre de la vista', hintText: 'Ej: PCs sin asignar', border: OutlineInputBorder(), isDense: true)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: f.isDefault
                    ? null
                    : () async {
                        final n = _name.text.trim();
                        if (n.isEmpty) return;
                        await ref.read(savedFiltersProvider.notifier).add(n, f);
                        _name.clear();
                      },
                child: const Text('Guardar'),
              ),
            ]),
            const Divider(height: 28),
            if (saved.isEmpty) const Text('Aún no tienes vistas guardadas.', style: TextStyle(color: Colors.grey)),
            for (final s in saved)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmark_outline),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(s.filter.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  ref.read(inventoryFilterProvider.notifier).state = s.filter;
                  Navigator.pop(context);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Borrar vista',
                  onPressed: () => ref.read(savedFiltersProvider.notifier).remove(s.name),
                ),
              ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
