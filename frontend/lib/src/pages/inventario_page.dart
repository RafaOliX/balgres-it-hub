import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/filters.dart';
import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';
import '../widgets/filter_sheet.dart';
import 'catalogos_page.dart';
import 'inventario_dashboard_page.dart';
import 'papelera_page.dart';

const _primary = Color(0xFF4F46E5);
const _bg = Color(0xFFF3F4F6);
const _border = Color(0xFFE5E7EB);

List<PopupMenuEntry<String>> _menuItems() => const <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'dashboard', child: Text('Dashboard')),
      PopupMenuItem(value: 'catalogos', child: Text('Empleados y ubicaciones')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'labels', child: Text('Etiquetas QR (PDF)')),
      PopupMenuItem(value: 'export', child: Text('Exportar Excel')),
      PopupMenuItem(value: 'import', child: Text('Importar Excel')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'trash', child: Text('Papelera')),
    ];

class InventarioPage extends ConsumerStatefulWidget {
  const InventarioPage({super.key});
  @override
  ConsumerState<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends ConsumerState<InventarioPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(inventoryFilterProvider).query;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => ref.invalidate(inventarioListProvider));

  Future<void> _refresh() async {
    ref.invalidate(inventarioListProvider);
    try {
      await ref.read(inventarioListProvider.future);
    } catch (_) {}
  }

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'dashboard':
        _push(const InventarioDashboardPage());
      case 'catalogos':
        _push(const CatalogosPage());
      case 'trash':
        _push(const PapeleraPage());
      case 'export':
        await _exportarExcel();
      case 'import':
        await _importarExcel();
      case 'labels':
        try {
          await ref.read(inventarioApiProvider).descargarEtiquetas();
          _snack('Descargando etiquetas...');
        } catch (e) {
          _snack('No se pudieron generar las etiquetas: ${apiError(e)}');
        }
    }
  }

  Future<void> _exportarExcel() async {
    try {
      await ref.read(inventarioApiProvider).descargarExcel();
      _snack('Descargando Excel...');
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _importarExcel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    try {
      final r = await ref.read(inventarioApiProvider).importarExcel(result.files.single.bytes!);
      ref.invalidate(inventarioListProvider);
      final errs = (r['errores'] as List?) ?? [];
      _snack('Importación: ${r['creados']} creados, ${r['omitidos']} ya existían, ${errs.length} con error');
      if (errs.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Filas con error'),
            content: SizedBox(width: 420, child: SingleChildScrollView(child: Text(errs.take(30).map((e) => 'Fila ${e['fila']}: ${e['detalle']}').join('\n')))),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
          ),
        );
      }
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(alignment: Alignment.center, children: [
          InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)),
          Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black54), onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ),
    );
  }

  /// Enter en el buscador (o lector de códigos): abre el activo si el tag coincide exacto o hay un solo resultado.
  void _onSubmit(String v, List<ItAsset> filtered, List<ItAsset> all) {
    final q = v.trim().toLowerCase();
    if (q.isEmpty) return;
    ItAsset? target = all.where((a) => a.assetTag.toLowerCase() == q).firstOrNull;
    target ??= filtered.length == 1 ? filtered.first : null;
    if (target == null) return;
    final f = ref.read(inventoryFilterProvider);
    ref.read(inventoryFilterProvider.notifier).state = f.copyWith(query: '');
    context.push('/inventario/detalle/${target.assetTag}').then((_) => ref.invalidate(inventarioListProvider));
  }

  @override
  Widget build(BuildContext context) {
    // mantiene el texto del buscador sincronizado cuando se limpia desde otro lado
    ref.listen<String>(inventoryFilterProvider.select((f) => f.query), (_, q) {
      if (_searchCtrl.text != q) {
        _searchCtrl.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
      }
    });

    final async = ref.watch(inventarioListProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    final items = async.valueOrNull ?? const <ItAsset>[];
    final filtered = applyFilter(items, filter);
    final groups = groupAssets(filtered, filter.groupBy);

    return Scaffold(
      backgroundColor: _bg,
      appBar: isMobile
          ? AppBar(
              title: const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              actions: [
                IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Categorías', onPressed: () => context.push('/categorias')),
                PopupMenuButton<String>(onSelected: _onMenu, itemBuilder: (_) => _menuItems()),
              ],
            )
          : null,
      body: Column(children: [
        _Toolbar(
          controller: _searchCtrl,
          focus: _searchFocus,
          items: items,
          shown: filtered.length,
          isMobile: isMobile,
          onMenu: _onMenu,
          onSubmit: (v) => _onSubmit(v, filtered, items),
          onRefresh: _refresh,
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Error: ${apiError(e)}'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _refresh, child: const Text('Reintentar')),
              ]),
            ),
            data: (_) {
              if (items.isEmpty) {
                return _EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aún no hay activos',
                  action: 'Registrar el primero',
                  onAction: () => context.push('/inventario/nuevo'),
                );
              }
              if (filtered.isEmpty) {
                return _EmptyState(
                  icon: Icons.search_off,
                  title: 'Sin resultados',
                  subtitle: 'Prueba con menos palabras o quita algún filtro.',
                  action: 'Limpiar filtros',
                  onAction: () => ref.read(inventoryFilterProvider.notifier).state = const InventoryFilter(),
                );
              }
              return LayoutBuilder(
                builder: (context, c) => c.maxWidth >= 900
                    ? _AssetsTable(groups: groups, onImageTap: _showImageDialog)
                    : _AssetsList(groups: groups, onRefresh: _refresh),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: isMobile
          ? FloatingActionButton(onPressed: () => context.push('/inventario/nuevo'), backgroundColor: _primary, child: const Icon(Icons.add, color: Colors.white))
          : null,
    );
  }
}

// ====================================================================== barra superior
class _Toolbar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final List<ItAsset> items;
  final int shown;
  final bool isMobile;
  final ValueChanged<String> onMenu;
  final ValueChanged<String> onSubmit;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.controller,
    required this.focus,
    required this.items,
    required this.shown,
    required this.isMobile,
    required this.onMenu,
    required this.onSubmit,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(inventoryFilterProvider);
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? const <Category>[];
    void set(InventoryFilter f) => ref.read(inventoryFilterProvider.notifier).state = f;

    // contadores de los chips: respetan búsqueda y demás filtros, pero no el estado
    final base = applyFilter(items, filter, ignoreStatus: true);
    int countStatus(String s) => base.where((a) => !a.isDraft && a.status == s).length;
    final chips = <(String, int, bool, VoidCallback)>[
      ('Todos', base.where((a) => !a.isDraft).length, filter.statuses.isEmpty && !filter.showDrafts,
          () => set(filter.copyWith(statuses: <String>{}, showDrafts: false))),
      for (final s in const ['Operativo', 'En Revisión', 'Retirado'])
        (s, countStatus(s), !filter.showDrafts && filter.statuses.length == 1 && filter.statuses.contains(s),
            () => set(filter.copyWith(statuses: {s}, showDrafts: false))),
      ('Borradores', base.where((a) => a.isDraft).length, filter.showDrafts,
          () => set(filter.copyWith(statuses: <String>{}, showDrafts: true))),
    ];

    final extra = <Widget>[
      for (final id in filter.categoryIds)
        _chip('Cat: ${cats.where((c) => c.id == id).firstOrNull?.name ?? id}', () => set(filter.copyWith(categoryIds: {...filter.categoryIds}..remove(id)))),
      for (final l in filter.locations) _chip('Ubic: $l', () => set(filter.copyWith(locations: {...filter.locations}..remove(l)))),
      if (filter.assign != AssignFilter.all) _chip(assignLabels[filter.assign]!, () => set(filter.copyWith(assign: AssignFilter.all))),
      if (filter.warranty != WarrantyFilter.all) _chip('Garantía: ${warrantyLabels[filter.warranty]}', () => set(filter.copyWith(warranty: WarrantyFilter.all))),
      if (filter.sort != 'recent') _chip('Orden: ${sortLabels[filter.sort]}', () => set(filter.copyWith(sort: 'recent'))),
      if (filter.groupBy != null) _chip('Agrupado: ${groupLabels[filter.groupBy]}', () => set(filter.copyWith(clearGroupBy: true))),
    ];

    final n = filter.panelCount;
    final totalFinal = items.where((a) => !a.isDraft).length;

    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 10 : 20, isMobile ? 16 : 24, 12),
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!isMobile) ...[
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Inventario', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('Activos de TI', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: onRefresh),
            const SizedBox(width: 4),
            OutlinedButton.icon(onPressed: () => onMenu('dashboard'), icon: const Icon(Icons.insights, size: 18), label: const Text('Dashboard')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => context.push('/categorias'), icon: const Icon(Icons.category_outlined, size: 18), label: const Text('Categorías')),
            PopupMenuButton<String>(onSelected: onMenu, itemBuilder: (_) => _menuItems(), tooltip: 'Más opciones'),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => context.push('/inventario/nuevo'), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo activo'), style: FilledButton.styleFrom(backgroundColor: _primary)),
          ]),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 46,
          child: TextField(
            controller: controller,
            focusNode: focus,
            autofocus: !isMobile,
            textInputAction: TextInputAction.search,
            onChanged: (v) => set(ref.read(inventoryFilterProvider).copyWith(query: v)),
            onSubmitted: onSubmit,
            decoration: InputDecoration(
              hintText: isMobile ? 'Buscar activo…' : 'Buscar por tag, marca, S/N, IP, MAC, ubicación, responsable…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Borrar búsqueda',
                      onPressed: () {
                        controller.clear();
                        set(ref.read(inventoryFilterProvider).copyWith(query: ''));
                        focus.requestFocus();
                      },
                    ),
              filled: true,
              fillColor: _bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in chips) _StatusChip(label: c.$1, count: c.$2, active: c.$3, onTap: c.$4),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => showFiltersSheet(context),
            icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.tune, size: 18)),
            label: const Text('Filtros'),
          ),
          IconButton(icon: const Icon(Icons.bookmarks_outlined), tooltip: 'Vistas guardadas', onPressed: () => showSavedViewsDialog(context)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('$shown de $totalFinal activos', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
          if (!filter.isDefault) TextButton(onPressed: () => set(const InventoryFilter()), child: const Text('Limpiar')),
        ]),
        if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 8, runSpacing: 4, children: extra)),
      ]),
    );
  }

  Widget _chip(String label, VoidCallback onDelete) => InputChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onDeleted: onDelete,
        visualDensity: VisualDensity.compact,
        backgroundColor: _bg,
      );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.count, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? _primary.withOpacity(0.1) : _bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? _primary : _border),
            ),
            child: Row(children: [
              Text(label, style: TextStyle(fontSize: 13, color: active ? _primary : Colors.black87, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: active ? _primary : _border, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: TextStyle(fontSize: 11, color: active ? Colors.white : Colors.black54, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
}

// ====================================================================== resultados
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String action;
  final VoidCallback onAction;
  const _EmptyState({required this.icon, required this.title, this.subtitle, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: const TextStyle(color: Colors.grey))),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(action)),
        ]),
      );
}

class _AssetsTable extends StatelessWidget {
  final Map<String, List<ItAsset>> groups;
  final void Function(String) onImageTap;
  const _AssetsTable({required this.groups, required this.onImageTap});

  Color _statusColor(String? s) => switch (s) { 'Operativo' => Colors.green, 'En Revisión' => Colors.orange, 'Retirado' => Colors.red, _ => Colors.grey };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in groups.entries) ...[
            if (e.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text('${e.key} (${e.value.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth - 50),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Activo')),
                      DataColumn(label: Text('Registro')),
                      DataColumn(label: Text('Cant.')),
                      DataColumn(label: Text('Categoría')),
                      DataColumn(label: Text('Marca / Modelo')),
                      DataColumn(label: Text('Ubicación')),
                      DataColumn(label: Text('Asignado a')),
                      DataColumn(label: Text('Estado')),
                    ],
                    rows: e.value.map((a) {
                      final col = _statusColor(a.status);
                      return DataRow(
                        onSelectChanged: (_) => context.push('/inventario/detalle/${a.assetTag}'),
                        cells: [
                          DataCell(Row(children: [
                            GestureDetector(onTap: () { if (a.imageUrl != null) onImageTap(a.imageUrl!); }, child: AssetThumbnail(asset: a, size: 40)),
                            const SizedBox(width: 8),
                            Text(a.assetTag, style: TextStyle(fontWeight: FontWeight.w600, color: a.isDraft ? Colors.grey : Colors.black)),
                            if (a.isDraft)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(label: const Text('Borrador', style: TextStyle(fontSize: 10)), backgroundColor: Colors.grey.shade200, visualDensity: VisualDensity.compact),
                              ),
                          ])),
                          DataCell(Text(a.createdAt.toString().substring(0, 10))),
                          DataCell(Text('${a.quantity} ${a.unit}')),
                          DataCell(Text(a.category)),
                          DataCell(Text('${a.brand} ${a.model}')),
                          DataCell(Text(a.location ?? '—')),
                          DataCell(Text(a.assignedTo ?? '—')),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(a.status ?? '—', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w600)),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ]),
      ),
    );
  }
}

class _AssetsList extends StatelessWidget {
  final Map<String, List<ItAsset>> groups;
  final Future<void> Function() onRefresh;
  const _AssetsList({required this.groups, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final rows = <Object>[];
    for (final e in groups.entries) {
      if (e.key.isNotEmpty) rows.add('${e.key} (${e.value.length})');
      rows.addAll(e.value);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = rows[i];
          if (r is String) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(r, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo)),
            );
          }
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: AssetCard(asset: r as ItAsset));
        },
      ),
    );
  }
}
