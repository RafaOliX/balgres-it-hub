import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';
import 'catalogos_page.dart';
import 'dashboard_page.dart';
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
  String _statusFilter = 'Todos';

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => ref.invalidate(inventarioListProvider));

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'dashboard':
        _push(const DashboardPage());
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventarioListProvider);
    final query = ref.watch(inventarioQueryProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: _bg,
      appBar: isMobile
          ? AppBar(
              title: const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              actions: [
                IconButton(icon: const Icon(Icons.category_outlined), onPressed: () => context.push('/categorias'), tooltip: 'Categorías'),
                PopupMenuButton<String>(onSelected: _onMenu, itemBuilder: (_) => _menuItems()),
              ],
            )
          : null,
      body: Column(children: [
        _Header(
          query: query, onQuery: (v) => ref.read(inventarioQueryProvider.notifier).state = v,
          onNew: () => context.push('/inventario/nuevo'), isMobile: isMobile, onMenu: _onMenu,
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: ${apiError(e)}')),
            data: (items) {
              final filtered = switch (_statusFilter) {
                'Todos' => items.where((a) => !a.isDraft).toList(),
                'Borradores' => items.where((a) => a.isDraft).toList(),
                _ => items.where((a) => !a.isDraft && a.status == _statusFilter).toList(),
              };
              return Column(children: [
                _StatusFilters(
                  current: _statusFilter, onChanged: (s) => setState(() => _statusFilter = s),
                  counts: {
                    'Todos': items.where((a) => !a.isDraft).length,
                    'Borradores': items.where((a) => a.isDraft).length,
                    'Operativo': items.where((a) => !a.isDraft && a.status == 'Operativo').length,
                    'En Revisión': items.where((a) => !a.isDraft && a.status == 'En Revisión').length,
                    'Retirado': items.where((a) => !a.isDraft && a.status == 'Retirado').length,
                  },
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Inventario vacío'))
                      : LayoutBuilder(builder: (context, c) => c.maxWidth >= 900
                          ? _AssetsTable(assets: filtered, onImageTap: (url) => _showImageDialog(context, url))
                          : _AssetsList(assets: filtered)),
                ),
              ]);
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

class _Header extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  final VoidCallback onNew;
  final bool isMobile;
  final ValueChanged<String> onMenu;
  const _Header({required this.query, required this.onQuery, required this.onNew, required this.isMobile, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 10 : 24, isMobile ? 16 : 24, 16),
      color: Colors.white,
      child: Column(children: [
        if (!isMobile)
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Inventario', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('Activos de TI', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            ),
            OutlinedButton.icon(onPressed: () => onMenu('dashboard'), icon: const Icon(Icons.insights, size: 18), label: const Text('Dashboard')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => context.push('/categorias'), icon: const Icon(Icons.category_outlined, size: 18), label: const Text('Categorías')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => onMenu('catalogos'), icon: const Icon(Icons.groups_outlined, size: 18), label: const Text('Empleados / Ubicaciones')),
            const SizedBox(width: 4),
            PopupMenuButton<String>(onSelected: onMenu, itemBuilder: (_) => _menuItems(), tooltip: 'Más'),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo activo'), style: FilledButton.styleFrom(backgroundColor: _primary)),
          ]),
        SizedBox(height: isMobile ? 0 : 16),
        SizedBox(
          height: 44,
          child: TextField(
            controller: TextEditingController(text: query)..selection = TextSelection.collapsed(offset: query.length),
            onChanged: onQuery,
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
}

class _StatusFilters extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;
  const _StatusFilters({required this.current, required this.onChanged, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: counts.entries.map((e) {
            final active = current == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onChanged(e.key), borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: active ? _primary.withOpacity(0.1) : _bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: active ? _primary : _border)),
                  child: Row(children: [
                    Text(e.key, style: TextStyle(fontSize: 13, color: active ? _primary : Colors.black87, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: active ? _primary : _border, borderRadius: BorderRadius.circular(10)),
                      child: Text('${e.value}', style: TextStyle(fontSize: 11, color: active ? Colors.white : Colors.black54, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _AssetsTable extends StatelessWidget {
  final List<ItAsset> assets;
  final Function(String) onImageTap;
  const _AssetsTable({required this.assets, required this.onImageTap});

  Color _statusColor(String? s) => switch (s) { 'Operativo' => Colors.green, 'En Revisión' => Colors.orange, 'Retirado' => Colors.red, _ => Colors.grey };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Activo')), DataColumn(label: Text('Registro')), DataColumn(label: Text('Cant.')),
            DataColumn(label: Text('Categoría')), DataColumn(label: Text('Marca / Modelo')), DataColumn(label: Text('Ubicación')),
            DataColumn(label: Text('Asignado a')), DataColumn(label: Text('Estado')),
          ],
          rows: assets.map((a) {
            final c = _statusColor(a.status);
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
                  decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(a.status ?? '—', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
                )),
              ],
            );
          }).toList(),
        ),
      ),
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
