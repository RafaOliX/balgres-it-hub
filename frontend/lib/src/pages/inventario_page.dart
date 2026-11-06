import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';

const _primary = Color(0xFF4F46E5);
const _bg = Color(0xFFFAFAFA);
const _border = Color(0xFFE5E7EB);

class InventarioPage extends ConsumerStatefulWidget {
  const InventarioPage({super.key});
  @override
  ConsumerState<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends ConsumerState<InventarioPage> {
  String _statusFilter = 'Todos';

  Future<void> _exportarExcel() async {
    final url = Uri.parse('http://192.168.0.10:8091/api/inventario/export');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _importarExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      try {
        await ref.read(inventarioApiProvider).importarExcel(result.files.single.bytes!);
        ref.invalidate(inventarioListProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel importado correctamente')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventarioListProvider);
    final query = ref.watch(inventarioQueryProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: _bg,
      appBar: isMobile ? AppBar(
        title: const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) { if (val == 'export') _exportarExcel(); if (val == 'import') _importarExcel(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'export', child: Text('Exportar Excel')),
              const PopupMenuItem(value: 'import', child: Text('Importar Excel')),
            ],
          )
        ],
      ) : null,
      body: Column(
        children: [
          _Header(
            query: query,
            onQuery: (v) => ref.read(inventarioQueryProvider.notifier).state = v,
            onNew: () => context.push('/inventario/nuevo'),
            isMobile: isMobile,
            onExport: _exportarExcel,
            onImport: _importarExcel,
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                final filtered = _statusFilter == 'Todos' ? items : items.where((a) => a.status == _statusFilter).toList();
                return Column(
                  children: [
                    _StatusFilters(
                      current: _statusFilter, onChanged: (s) => setState(() => _statusFilter = s),
                      counts: {
                        'Todos': items.length,
                        'Operativo': items.where((a) => a.status == 'Operativo').length,
                        'En Revisión': items.where((a) => a.status == 'En Revisión').length,
                        'Retirado': items.where((a) => a.status == 'Retirado').length,
                      },
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Inventario vacío'))
                          : LayoutBuilder(builder: (context, c) {
                              return c.maxWidth >= 900 ? _AssetsTable(assets: filtered) : _AssetsList(assets: filtered);
                            }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isMobile ? FloatingActionButton(
        onPressed: () => context.push('/inventario/nuevo'),
        backgroundColor: _primary,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }
}

class _Header extends StatelessWidget {
  final String query; final ValueChanged<String> onQuery; final VoidCallback onNew;
  final bool isMobile; final VoidCallback onExport; final VoidCallback onImport;

  const _Header({required this.query, required this.onQuery, required this.onNew, required this.isMobile, required this.onExport, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 10 : 24, isMobile ? 16 : 24, 16),
      color: Colors.white,
      child: Column(
        children: [
          if (!isMobile)
            Row(
              children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Inventario', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    Text('Activos de TI', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
                ),
                OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Importar')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: onExport, icon: const Icon(Icons.download, size: 18), label: const Text('Exportar')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo activo'), style: FilledButton.styleFrom(backgroundColor: _primary)),
              ],
            ),
          SizedBox(height: isMobile ? 0 : 16),
          SizedBox(
            height: 44,
            child: TextField(
              controller: TextEditingController(text: query)..selection = TextSelection.collapsed(offset: query.length),
              onChanged: onQuery,
              decoration: InputDecoration(
                hintText: 'Buscar activo...', prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: _bg, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  final String current; final ValueChanged<String> onChanged; final Map<String, int> counts;
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
                  decoration: BoxDecoration(
                    color: active ? _primary.withOpacity(0.1) : _bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? _primary : _border),
                  ),
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
  const _AssetsTable({required this.assets});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Activo')), DataColumn(label: Text('Cant.')), DataColumn(label: Text('Categoría')),
            DataColumn(label: Text('Marca / Modelo')), DataColumn(label: Text('Ubicación')), DataColumn(label: Text('Estado')),
          ],
          rows: assets.map((a) {
            final c = _statusColor(a.status);
            return DataRow(
              onSelectChanged: (_) => context.push('/inventario/detalle/${a.assetTag}'),
              cells: [
                DataCell(Row(children: [AssetThumbnail(asset: a, size: 32), const SizedBox(width: 8), Text(a.assetTag, style: const TextStyle(fontWeight: FontWeight.w600))])),
                DataCell(Text('${a.quantity} ${a.unit}')),
                DataCell(Text(a.category)),
                DataCell(Text('${a.brand} ${a.model}')),
                DataCell(Text(a.location ?? '—')),
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
  Color _statusColor(String? s) => switch (s) { 'Operativo' => Colors.green, 'En Revisión' => Colors.orange, 'Retirado' => Colors.red, _ => Colors.grey };
}

class _AssetsList extends StatelessWidget {
  final List<ItAsset> assets;
  const _AssetsList({required this.assets});
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: assets.length,
      itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AssetCard(asset: assets[i])),
    );
  }
}
