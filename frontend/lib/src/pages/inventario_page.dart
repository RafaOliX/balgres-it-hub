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
  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => ref.invalidate(inventarioListProvider));

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'dashboard': _push(const InventarioDashboardPage());
      case 'catalogos': _push(const CatalogosPage());
      case 'trash': _push(const PapeleraPage());
      case 'export': await _exportarExcel();
      case 'import': await _importarExcel();
      case 'labels':
        try {
          await ref.read(inventarioApiProvider).descargarEtiquetas();
          _snack('Descargando etiquetas...');
        } catch (e) {
          _snack('No se pudieron generar las etiquetas (¿falta segno en el backend?)');
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

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(16),
        child: Stack(alignment: Alignment.center, children: [
          InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)),
          Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black54), onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ),
    );
  }

  void _showFiltersModal(BuildContext context, WidgetRef ref) {
    final cats = ref.read(categoriasListProvider).valueOrNull ?? <Category>[];
    final filter = ref.read(inventoryFilterProvider);
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Filtros Avanzados'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Estado', style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(spacing: 8, children: [
                      FilterChip(
                        label: const Text('Borradores'),
                        selected: filter.showDrafts,
                        onSelected: (v) {
                          final newFilter = filter.copyWith(showDrafts: v, statuses: v ? {} : filter.statuses);
                          ref.read(inventoryFilterProvider.notifier).state = newFilter;
                          setModalState(() {});
                        },
                      ),
                      ...['Operativo', 'En Revisión', 'Retirado'].map((s) => FilterChip(
                        label: Text(s),
                        selected: filter.statuses.contains(s),
                        onSelected: (v) {
                          final set = {...filter.statuses};
                          if (v) set.add(s); else set.remove(s);
                          final newFilter = filter.copyWith(statuses: set, showDrafts: false);
                          ref.read(inventoryFilterProvider.notifier).state = newFilter;
                          setModalState(() {});
                        },
                      )),
                    ]),
                    const SizedBox(height: 16),
                    const Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(spacing: 8, children: cats.map((c) => FilterChip(
                      label: Text(c.name),
                      selected: filter.categoryIds.contains(c.id),
                      onSelected: (v) {
                        final set = {...filter.categoryIds};
                        if (v) set.add(c.id); else set.remove(c.id);
                        final newFilter = filter.copyWith(categoryIds: set);
                        ref.read(inventoryFilterProvider.notifier).state = newFilter;
                        setModalState(() {});
                      },
                    )).toList()),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(inventoryFilterProvider.notifier).state = const InventoryFilter();
                  Navigator.pop(ctx);
                },
                child: const Text('Limpiar todo'),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aplicar')),
            ],
          );
        },
      ),
    );
  }

  void _showSaveFilterDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar Vista Favorita'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre de la vista', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await ref.read(savedFiltersProvider.notifier).add(nameCtrl.text, ref.read(inventoryFilterProvider));
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventarioListProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: _bg,
      appBar: isMobile
          ? AppBar(
              title: const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: Badge(isLabelVisible: filter.isActive, child: const Icon(Icons.filter_list)),
                  tooltip: 'Filtros',
                  onPressed: () => _showFiltersModal(context, ref),
                ),
                IconButton(
                  icon: Icon(Icons.star, color: filter.isActive ? Colors.amber : Colors.grey),
                  tooltip: 'Guardar vista',
                  onPressed: () => _showSaveFilterDialog(context, ref),
                ),
                PopupMenuButton<String>(onSelected: _onMenu, itemBuilder: (_) => _menuItems()),
              ],
            )
          : null,
      body: Column(children: [
        _Header(
          isMobile: isMobile, 
          onMenu: _onMenu,
          onShowFilters: () => _showFiltersModal(context, ref),
          onSaveFilter: () => _showSaveFilterDialog(context, ref),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: ${apiError(e)}')),
            data: (items) {
              // 1. Filtrar
              final filtered = items.where((a) {
                if (filter.showDrafts == false && a.isDraft) return false;
                if (filter.showDrafts == true && !a.isDraft) return false;
                if (filter.statuses.isNotEmpty && !filter.statuses.contains(a.status)) return false;
                if (filter.categoryIds.isNotEmpty && !filter.categoryIds.contains(a.categoryId)) return false;
                if (filter.searchQuery.isNotEmpty) {
                  final q = filter.searchQuery.toLowerCase();
                  return a.assetTag.toLowerCase().contains(q) || a.brand.toLowerCase().contains(q) || a.model.toLowerCase().contains(q);
                }
                return true;
              }).toList();

              // 2. Agrupar
              final Map<String, List<ItAsset>> grouped = {};
              if (filter.groupBy != null) {
                for (final a in filtered) {
                  final key = switch (filter.groupBy) {
                    'category' => a.category,
                    'status' => a.status ?? 'Sin Estado',
                    'location' => a.location ?? 'Sin Ubicación',
                    _ => 'Otros',
                  };
                  grouped.putIfAbsent(key, () => []).add(a);
                }
              } else {
                grouped['Todos'] = filtered;
              }

              if (filtered.isEmpty) return const Center(child: Text('No hay resultados con los filtros actuales'));

              return LayoutBuilder(builder: (context, c) => c.maxWidth >= 900
                  ? _AssetsTable(grouped: grouped, onImageTap: (url) => _showImageDialog(context, url))
                  : _AssetsList(assets: filtered));
            },
          ),
        ),
      ]),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => context.push('/inventario/nuevo'),
              backgroundColor: _primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  final bool isMobile;
  final ValueChanged<String> onMenu;
  final VoidCallback onShowFilters;
  final VoidCallback onSaveFilter;
  
  const _Header({
    required this.isMobile, 
    required this.onMenu,
    required this.onShowFilters,
    required this.onSaveFilter,
  });

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: ref.read(inventoryFilterProvider).searchQuery);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(inventoryFilterProvider);
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? <Category>[];

    return Container(
      padding: EdgeInsets.fromLTRB(widget.isMobile ? 16 : 24, widget.isMobile ? 10 : 24, widget.isMobile ? 16 : 24, 16),
      color: Colors.white,
      child: Column(children: [
        if (!widget.isMobile)
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Inventario', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('Activos de TI', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            ),
            
            // BOTÓN DE FILTROS
            OutlinedButton.icon(
              onPressed: widget.onShowFilters,
              icon: Badge(
                isLabelVisible: filter.isActive,
                child: const Icon(Icons.filter_list, size: 18),
              ),
              label: const Text('Filtros'),
            ),
            const SizedBox(width: 8),

            // BOTÓN DE AGRUPAR
            PopupMenuButton<String>(
              onSelected: (v) => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(groupBy: v == 'none' ? null : v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'none', child: Text('Sin agrupar')),
                PopupMenuItem(value: 'category', child: Text('Agrupar por Categoría')),
                PopupMenuItem(value: 'status', child: Text('Agrupar por Estado')),
                PopupMenuItem(value: 'location', child: Text('Agrupar por Ubicación')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.view_agenda, size: 18),
                  const SizedBox(width: 8),
                  Text(filter.groupBy == null ? 'Agrupar' : 'Agrupado'),
                ]),
              ),
            ),
            const SizedBox(width: 8),

            // BOTÓN DE FAVORITOS
            IconButton(
              icon: Icon(Icons.star, color: filter.isActive ? Colors.amber : Colors.grey),
              tooltip: 'Guardar vista actual',
              onPressed: widget.onSaveFilter,
            ),

            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => context.push('/inventario/nuevo'), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo activo'), style: FilledButton.styleFrom(backgroundColor: _primary)),
          ]),
        
        // Chips de filtros activos
        if (filter.statuses.isNotEmpty || filter.categoryIds.isNotEmpty || filter.showDrafts || filter.groupBy != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (filter.showDrafts) _chip(context, 'Borradores', () => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(showDrafts: false)),
            ...filter.statuses.map((s) => _chip(context, 'Estado: $s', () => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(statuses: ({...filter.statuses}..remove(s))))),
            ...filter.categoryIds.map((id) => _chip(context, 'Cat: ${cats.where((c) => c.id == id).firstOrNull?.name ?? id}', () => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(categoryIds: ({...filter.categoryIds}..remove(id))))),
            if (filter.groupBy != null) _chip(context, 'Agrupado por: ${filter.groupBy}', () => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(groupBy: null)),
          ]),
        ],

        SizedBox(height: widget.isMobile ? 0 : 16),
        SizedBox(
          height: 44,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => ref.read(inventoryFilterProvider.notifier).state = filter.copyWith(searchQuery: v),
            decoration: InputDecoration(
              hintText: 'Buscar por tag, marca, S/N, ubicación, responsable...', prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: _bg, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onDelete) {
    return InputChip(
      label: Text(label),
      onDeleted: onDelete,
      deleteIconColor: Colors.red,
      backgroundColor: const Color(0xFFF3F4F6),
    );
  }
}

class _AssetsTable extends StatelessWidget {
  final Map<String, List<ItAsset>> grouped;
  final Function(String) onImageTap;
  const _AssetsTable({required this.grouped, required this.onImageTap});

  Color _statusColor(String? s) => switch (s) { 'Operativo' => Colors.green, 'En Revisión' => Colors.orange, 'Retirado' => Colors.red, _ => Colors.grey };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grouped.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Activo')), DataColumn(label: Text('Registro')), DataColumn(label: Text('Cant.')),
                  DataColumn(label: Text('Categoría')), DataColumn(label: Text('Marca / Modelo')), DataColumn(label: Text('Ubicación')),
                  DataColumn(label: Text('Asignado a')), DataColumn(label: Text('Estado')),
                ],
                rows: entry.value.map((a) {
                  final c = _statusColor(a.status);
                  return DataRow(
                    onSelectChanged: (_) => context.push('/inventario/detalle/${a.assetTag}'),
                    cells: [
                      DataCell(Row(children: [
                        GestureDetector(onTap: () { if (a.imageUrl != null) onImageTap(a.imageUrl!); }, child: AssetThumbnail(asset: a, size: 40)),
                        const SizedBox(width: 8),
                        Text(a.assetTag, style: TextStyle(fontWeight: FontWeight.w600, color: a.isDraft ? Colors.grey : Colors.black)),
                        if (a.isDraft) Padding(padding: const EdgeInsets.only(left: 8), child: Chip(label: const Text('Borrador', style: TextStyle(fontSize: 10)), backgroundColor: Colors.grey.shade200, visualDensity: VisualDensity.compact)),
                      ])),
                      DataCell(Text(a.createdAt.toString().substring(0, 10))),
                      DataCell(Text('${a.quantity} ${a.unit}')),
                      DataCell(Text(a.category)),
                      DataCell(Text('${a.brand} ${a.model}')),
                      DataCell(Text(a.location ?? '—')),
                      DataCell(Text(a.assignedTo ?? '—')),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(a.status ?? '—', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      }).toList()),
    );
  }
}

class _AssetsList extends StatelessWidget {
  final List<ItAsset> assets;
  const _AssetsList({required this.assets});
  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(16), itemCount: assets.length,
        itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AssetCard(asset: assets[i])),
      );
}
