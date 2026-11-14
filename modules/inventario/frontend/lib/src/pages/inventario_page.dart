import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/filters.dart';
import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../data/table_prefs.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';
import '../widgets/bulk_bar.dart';
import '../widgets/columns_dialog.dart';
import '../widgets/filter_sheet.dart';
import 'catalogos_page.dart';
import 'inventario_dashboard_page.dart';
import 'papelera_page.dart';

List<PopupMenuEntry<String>> _menuItems() => const <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'dashboard', child: Text('Dashboard')),
      PopupMenuItem(value: 'catalogos', child: Text('Ubicaciones')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'labels', child: Text('Etiquetas QR (todas)')),
      PopupMenuItem(value: 'export', child: Text('Exportar Excel')),
      PopupMenuItem(value: 'import', child: Text('Importar Excel')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'drafts', child: Text('Limpiar borradores antiguos')),
      PopupMenuItem(value: 'trash', child: Text('Papelera')),
    ];

class _GroupHeader {
  final String label;
  final int count;
  const _GroupHeader(this.label, this.count);
}

class InventarioPage extends ConsumerStatefulWidget {
  const InventarioPage({super.key});
  @override
  ConsumerState<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends ConsumerState<InventarioPage> with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _poll;
  Timer? _debounce;
  String? _version;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(inventoryFilterProvider).query;
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) _silentRefresh();
  }

  /// Consulta una huella mínima y solo recarga la lista si algo cambió.
  Future<void> _silentRefresh() async {
    if (!mounted || !_visible) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    try {
      final v = await ref.read(inventarioApiProvider).getVersion();
      if (v != _version) {
        _version = v;
        ref.invalidate(inventarioListProvider);
      }
    } catch (_) {}
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final f = ref.read(inventoryFilterProvider);
      ref.read(inventoryFilterProvider.notifier).state = f.copyWith(query: v);
    });
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => ref.invalidate(inventarioListProvider));

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
      case 'drafts':
        await _limpiarBorradores();
      case 'labels':
        try {
          await ref.read(inventarioApiProvider).descargarEtiquetas();
          _snack('Descargando etiquetas...');
        } catch (e) {
          _snack('No se pudieron generar las etiquetas: ${apiError(e)}');
        }
    }
  }

  Future<void> _limpiarBorradores() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar borradores'),
        content: const Text('Se eliminarán definitivamente los borradores sin finalizar con más de 7 días.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref.read(inventarioApiProvider).limpiarBorradores(dias: 7);
      ref.invalidate(inventarioListProvider);
      _snack('$n borrador(es) eliminados');
    } catch (e) {
      _snack('Error: ${apiError(e)}');
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

  void _onSubmit(String v, List<ItAsset> filtered, List<ItAsset> all) {
    final q = v.trim().toLowerCase();
    if (q.isEmpty) return;
    ItAsset? target = all.where((a) => a.assetTag.toLowerCase() == q).firstOrNull;
    target ??= filtered.length == 1 ? filtered.first : null;
    if (target == null) return;
    final f = ref.read(inventoryFilterProvider);
    ref.read(inventoryFilterProvider.notifier).state = f.copyWith(query: '');
    openAsset(context, target.assetTag);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(inventoryFilterProvider.select((f) => f.query), (_, q) {
      if (_searchCtrl.text != q && (q.isEmpty || !_searchFocus.hasFocus)) {
        _searchCtrl.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
      }
    });

    final async = ref.watch(inventarioListProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final sel = ref.watch(selectionProvider);
    final colState = ref.watch(columnsProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    final items = async.valueOrNull ?? const <ItAsset>[];
    final filtered = ref.watch(filteredAssetsProvider);
    final groups = groupAssets(filtered, filter.groupBy);
    final rows = <Object>[
      for (final e in groups.entries) ...[
        if (e.key.isNotEmpty) _GroupHeader(e.key, e.value.length),
        ...e.value,
      ],
    ];
    final allCols = allColumns(items);
    final byId = {for (final d in allCols) d.id: d};
    final visibleCols = [for (final id in colState.visible) if (byId[id] != null) byId[id]!];

    Widget body;
    if (items.isEmpty && async.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty && async.hasError) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Error: ${apiError(async.error!)}'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _refresh, child: const Text('Reintentar')),
        ]),
      );
    } else if (items.isEmpty) {
      body = EmptyState(icon: Icons.inventory_2_outlined, title: 'Aún no hay activos', action: 'Registrar el primero', onAction: () => openNewAsset(context));
    } else if (filtered.isEmpty) {
      body = EmptyState(
        icon: Icons.search_off,
        title: 'Sin resultados',
        subtitle: 'Prueba con menos palabras o quita algún filtro.',
        action: 'Limpiar filtros',
        onAction: () => ref.read(inventoryFilterProvider.notifier).state = const InventoryFilter(),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 760
            ? _DesktopTable(rows: rows, cols: visibleCols, allTags: filtered.map((a) => a.assetTag).toList(), onImageTap: _showImageDialog)
            : _MobileList(rows: rows, onRefresh: _refresh),
      );
    }

    final pad = isMobile ? 12.0 : 24.0;
    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: const Text('Inventario'),
              actions: [
                const ThemeToggleButton(),
                IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Categorías', onPressed: () => context.push('/categorias')),
                PopupMenuButton<String>(onSelected: _onMenu, itemBuilder: (_) => _menuItems()),
              ],
            )
          : null,
      body: Padding(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
        child: Column(children: [
          _Toolbar(
            controller: _searchCtrl,
            focus: _searchFocus,
            items: items,
            shown: filtered.length,
            isMobile: isMobile,
            onMenu: _onMenu,
            onSubmit: (v) => _onSubmit(v, filtered, items),
            onRefresh: _refresh,
            onColumns: () => showColumnsDialog(context, allCols),
            onQuery: _onQuery,
          ),
          if (sel.isNotEmpty) BulkBar(selected: items.where((a) => sel.contains(a.assetTag)).toList()),
          const SizedBox(height: 14),
          Expanded(child: body),
        ]),
      ),
      floatingActionButton: isMobile ? FloatingActionButton(onPressed: () => openNewAsset(context), child: const Icon(Icons.add)) : null,
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
  final VoidCallback onColumns;
  final ValueChanged<String> onQuery;

  const _Toolbar({
    required this.controller, required this.focus, required this.items, required this.shown, required this.isMobile,
    required this.onMenu, required this.onSubmit, required this.onRefresh, required this.onColumns, required this.onQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final filter = ref.watch(inventoryFilterProvider);
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? const <Category>[];
    void set(InventoryFilter f) => ref.read(inventoryFilterProvider.notifier).state = f;

    final base = ref.watch(statusBaseProvider);
    int countStatus(String s) => base.where((a) => !a.isDraft && a.status == s).length;
    final tabs = <(String, int, bool, VoidCallback)>[
      ('Todos', base.where((a) => !a.isDraft).length, filter.statuses.isEmpty && !filter.showDrafts, () => set(filter.copyWith(statuses: <String>{}, showDrafts: false))),
      for (final s in const ['Operativo', 'En Revisión', 'Retirado'])
        (s, countStatus(s), !filter.showDrafts && filter.statuses.length == 1 && filter.statuses.contains(s), () => set(filter.copyWith(statuses: {s}, showDrafts: false))),
      ('Borradores', base.where((a) => a.isDraft).length, filter.showDrafts, () => set(filter.copyWith(statuses: <String>{}, showDrafts: true))),
    ];

    final extra = <Widget>[
      for (final id in filter.categoryIds)
        _chip('Cat: ${cats.where((x) => x.id == id).firstOrNull?.name ?? id}', () => set(filter.copyWith(categoryIds: {...filter.categoryIds}..remove(id)))),
      for (final l in filter.locations) _chip('Ubic: $l', () => set(filter.copyWith(locations: {...filter.locations}..remove(l)))),
      if (filter.assign != AssignFilter.all) _chip(assignLabels[filter.assign]!, () => set(filter.copyWith(assign: AssignFilter.all))),
      if (filter.sort != 'recent') _chip('Orden: ${sortLabels[filter.sort]}', () => set(filter.copyWith(sort: 'recent'))),
      if (filter.sortCol != null)
        _chip(
          'Orden: ${kBaseColumns.where((d) => d.id == filter.sortCol).firstOrNull?.label ?? filter.sortCol!.replaceFirst('spec:', '')} ${filter.sortAsc ? '↑' : '↓'}',
          () => set(filter.copyWith(clearSortCol: true, sortAsc: true)),
        ),
      if (filter.groupBy != null) _chip('Agrupado: ${groupLabels[filter.groupBy]}', () => set(filter.copyWith(clearGroupBy: true))),
    ];

    final n = filter.panelCount;
    final totalFinal = items.where((a) => !a.isDraft).length;

    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 22, isMobile ? 14 : 20, isMobile ? 14 : 22, 8),
      decoration: cardDeco(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!isMobile) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Inventario', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
                const SizedBox(height: 6),
                Text('$totalFinal activos de TI', style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: onRefresh),
            const SizedBox(width: 4),
            OutlinedButton.icon(onPressed: () => onMenu('dashboard'), icon: const Icon(Icons.insights, size: 18), label: const Text('Dashboard')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => context.push('/categorias'), icon: const Icon(Icons.category_outlined, size: 18), label: const Text('Categorías')),
            PopupMenuButton<String>(onSelected: onMenu, itemBuilder: (_) => _menuItems(), tooltip: 'Más opciones'),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => openNewAsset(context), icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo activo')),
          ]),
          const SizedBox(height: 18),
        ],
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            focusNode: focus,
            autofocus: !isMobile,
            textInputAction: TextInputAction.search,
            onChanged: onQuery,
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
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final t in tabs) _StatusPill(label: t.$1, count: t.$2, active: t.$3, onTap: t.$4)]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => showFiltersSheet(context),
            icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.tune, size: 18)),
            label: const Text('Filtros'),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: onColumns, icon: const Icon(Icons.view_column_outlined, size: 18), label: const Text('Columnas')),
          ],
          IconButton(icon: const Icon(Icons.bookmarks_outlined), tooltip: 'Vistas guardadas', onPressed: () => showSavedViewsDialog(context)),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: Text('$shown de $totalFinal', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted))),
          ),
          if (!filter.isDefault) TextButton(onPressed: () => set(const InventoryFilter()), child: const Text('Limpiar')),
        ]),
        if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6, top: 6), child: Wrap(spacing: 8, runSpacing: 4, children: extra)),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _chip(String label, VoidCallback onDelete) => InputChip(label: Text(label, style: const TextStyle(fontSize: 12)), onDeleted: onDelete, visualDensity: VisualDensity.compact);
}

class _StatusPill extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _StatusPill({required this.label, required this.count, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.accent.withValues(alpha: 0.13) : c.panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: active ? c.accent : c.line),
          ),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? c.accent : c.ink)),
            const SizedBox(width: 8),
            Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? c.accent : c.muted)),
          ]),
        ),
      ),
    );
  }
}

// ====================================================================== tabla (escritorio)
class _DesktopTable extends ConsumerWidget {
  final List<Object> rows;
  final List<ColumnDef> cols;
  final List<String> allTags;
  final void Function(String) onImageTap;
  const _DesktopTable({required this.rows, required this.cols, required this.allTags, required this.onImageTap});

  Widget _cell(BuildContext context, ColumnDef col, ItAsset a) {
    final c = context.sw;
    Widget child;
    switch (col.id) {
      case 'asset':
        child = Row(children: [
          GestureDetector(onTap: () { if (a.imageUrl != null) onImageTap(a.imageUrl!); }, child: AssetThumbnail(asset: a, size: 34)),
          const SizedBox(width: 10),
          Flexible(child: Text(a.assetTag, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: a.isDraft ? c.muted : c.ink))),
        ]);
      case 'status':
        child = StatusTag(status: a.status, draft: a.isDraft);
      case 'equipo':
        child = Text(col.text(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500));
      default:
        final t = col.text(a);
        child = Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t == '—' ? c.muted : c.ink));
    }
    return SizedBox(width: col.width, child: Padding(padding: const EdgeInsets.only(right: 12), child: Align(alignment: Alignment.centerLeft, child: child)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final sel = ref.watch(selectionProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final totalW = 56 + cols.fold<double>(0, (s, e) => s + e.width) + 24;
    final allSelected = allTags.isNotEmpty && allTags.every(sel.contains);
    final some = sel.isNotEmpty && !allSelected;

    void toggle(String tag) {
      final n = {...sel};
      n.contains(tag) ? n.remove(tag) : n.add(tag);
      ref.read(selectionProvider.notifier).state = n;
    }

    return Container(
      decoration: cardDeco(context),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (ctx, cs) {
        final w = totalW > cs.maxWidth ? totalW : cs.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: w,
            height: cs.maxHeight,
            child: Column(children: [
              Container(
                height: 48,
                color: c.panel,
                child: Row(children: [
                  SizedBox(
                    width: 56,
                    child: Checkbox(
                      tristate: true,
                      value: allSelected ? true : (some ? null : false),
                      onChanged: (_) => ref.read(selectionProvider.notifier).state = allSelected ? <String>{} : {...allTags},
                    ),
                  ),
                  for (final col in cols)
                    InkWell(
                      onTap: () => ref.read(inventoryFilterProvider.notifier).state = nextColumnSort(filter, col.id),
                      child: SizedBox(
                        width: col.width,
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(children: [
                            Flexible(child: SectionLabel(col.label)),
                            if (filter.sortCol == col.id)
                              Padding(padding: const EdgeInsets.only(left: 4), child: Icon(filter.sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: c.accent)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              Divider(height: 1, color: c.line),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    if (r is _GroupHeader) {
                      return Container(
                        height: 40,
                        padding: const EdgeInsets.only(left: 20),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.06), border: Border(bottom: BorderSide(color: c.line))),
                        child: Row(children: [
                          Text(r.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.accent)),
                          const SizedBox(width: 8),
                          Text('${r.count}', style: TextStyle(fontSize: 12, color: c.muted)),
                        ]),
                      );
                    }
                    final a = r as ItAsset;
                    final selected = sel.contains(a.assetTag);
                    return InkWell(
                      onTap: () => sel.isNotEmpty ? toggle(a.assetTag) : openAsset(context, a.assetTag),
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(color: selected ? c.accent.withValues(alpha: 0.08) : null, border: Border(bottom: BorderSide(color: c.line))),
                        child: Row(children: [
                          SizedBox(width: 56, child: Checkbox(value: selected, onChanged: (_) => toggle(a.assetTag))),
                          for (final col in cols) _cell(context, col, a),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

// ====================================================================== lista (móvil)
class _MobileList extends ConsumerWidget {
  final List<Object> rows;
  final Future<void> Function() onRefresh;
  const _MobileList({required this.rows, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(selectionProvider);
    void toggle(String tag) {
      final n = {...sel};
      n.contains(tag) ? n.remove(tag) : n.add(tag);
      ref.read(selectionProvider.notifier).state = n;
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = rows[i];
          if (r is _GroupHeader) {
            return Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4),
              child: Text('${r.label} (${r.count})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.sw.accent)),
            );
          }
          final a = r as ItAsset;
          return AssetCard(asset: a, selected: sel.contains(a.assetTag), selectionMode: sel.isNotEmpty, onToggle: () => toggle(a.assetTag));
        },
      ),
    );
  }
}
