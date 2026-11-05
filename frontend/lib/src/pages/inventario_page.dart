import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';
import '../widgets/asset_card.dart';
import '../widgets/asset_thumbnail.dart';

const _primary = Color(0xFF4F46E5);
const _bg = Color(0xFFFAFAFA);
const _border = Color(0xFFE5E7EB);
const _textSecondary = Color(0xFF6B7280);
const _success = Color(0xFF10B981);
const _warning = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

class InventarioPage extends ConsumerStatefulWidget {
  const InventarioPage({super.key});

  @override
  ConsumerState<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends ConsumerState<InventarioPage> {
  String _statusFilter = 'Todos';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventarioListProvider);
    final query = ref.watch(inventarioQueryProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _Header(
            query: query,
            onQuery: (v) =>
                ref.read(inventarioQueryProvider.notifier).state = v,
            onNew: () => context.push('/inventario/nuevo'),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e'),
                ),
              ),
              data: (items) {
                final filtered = _statusFilter == 'Todos'
                    ? items
                    : items.where((a) => a.status == _statusFilter).toList();
                return Column(
                  children: [
                    _StatusFilters(
                      current: _statusFilter,
                      onChanged: (s) => setState(() => _statusFilter = s),
                      counts: {
                        'Todos': items.length,
                        'Operativo':
                            items.where((a) => a.status == 'Operativo').length,
                        'En Revisión':
                            items.where((a) => a.status == 'En Revisión').length,
                        'Retirado':
                            items.where((a) => a.status == 'Retirado').length,
                      },
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? _EmptyState(hasQuery: query.isNotEmpty)
                          : LayoutBuilder(builder: (context, c) {
                              return c.maxWidth >= 900
                                  ? _AssetsTable(assets: filtered)
                                  : _AssetsList(assets: filtered);
                            }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  final VoidCallback onNew;

  const _Header({
    required this.query,
    required this.onQuery,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inventario',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Activos de TI del departamento',
                        style: TextStyle(
                            fontSize: 13, color: _textSecondary)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo activo'),
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: TextField(
              controller: TextEditingController(text: query)
                ..selection = TextSelection.collapsed(offset: query.length),
              onChanged: onQuery,
              decoration: const InputDecoration(
                hintText: 'Buscar por tag, marca, modelo, S/N o ubicación…',
                prefixIcon: Icon(Icons.search, size: 20),
                filled: true,
                fillColor: _bg,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _primary, width: 1.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;

  const _StatusFilters({
    required this.current,
    required this.onChanged,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: Colors.white,
      child: Row(
        children: counts.entries.map((e) {
          final active = current == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => onChanged(e.key),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _primary.withOpacity(0.1) : _bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? _primary : _border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? _primary : Colors.black87,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: active ? _primary : _border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${e.value}',
                        style: TextStyle(
                          fontSize: 11,
                          color: active ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
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
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(_bg),
          dataRowMinHeight: 64,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Activo')),
            DataColumn(label: Text('Categoría')),
            DataColumn(label: Text('Marca / Modelo')),
            DataColumn(label: Text('S/N')),
            DataColumn(label: Text('Ubicación')),
            DataColumn(label: Text('Estado')),
          ],
          rows: assets.map((a) {
            final c = _statusColor(a.status);
            return DataRow(
              onSelectChanged: (_) {
                context.push('/inventario/detalle/${a.assetTag}');
              },
              cells: [
                DataCell(
                  Row(
                    children: [
                      AssetThumbnail(asset: a, size: 32),
                      const SizedBox(width: 8),
                      Text(a.assetTag,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                DataCell(Text(a.category, style: const TextStyle(fontSize: 13))),
                DataCell(Text('${a.brand} ${a.model}',
                    style: const TextStyle(fontSize: 13))),
                DataCell(Text(a.serialNumber,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12))),
                DataCell(Text(a.location ?? '—',
                    style: const TextStyle(fontSize: 13))),
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    a.status ?? '—',
                    style: TextStyle(
                        color: c,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _statusColor(String? s) => switch (s) {
        'Operativo' => _success,
        'En Revisión' => _warning,
        'Retirado' => _danger,
        _ => _textSecondary,
      };
}

class _AssetsList extends StatelessWidget {
  final List<ItAsset> assets;
  const _AssetsList({required this.assets});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: assets.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AssetCard(asset: assets[i]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.inventory_2_outlined,
            size: 64,
            color: _textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery
                ? 'Sin resultados para la búsqueda'
                : 'Aún no hay activos registrados',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Prueba con otro término'
                : 'Pulsa "Nuevo activo" para empezar',
            style: const TextStyle(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}
