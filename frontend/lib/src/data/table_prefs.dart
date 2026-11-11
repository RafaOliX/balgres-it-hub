import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/it_asset.dart';

String _d(DateTime? d) => d == null ? '—' : dateToApi(d)!;
String _s(String? v) => (v == null || v.trim().isEmpty) ? '—' : v;

class ColumnDef {
  final String id, label;
  final double width;
  final String Function(ItAsset) text;
  const ColumnDef(this.id, this.label, this.width, this.text);
  bool get isSpec => id.startsWith('spec:');
}

final List<ColumnDef> kBaseColumns = [
  ColumnDef('asset', 'Activo', 210, (a) => a.assetTag),
  ColumnDef('equipo', 'Equipo', 210, (a) => '${a.brand} ${a.model}'),
  ColumnDef('category', 'Categoría', 150, (a) => a.category),
  ColumnDef('brand', 'Marca', 120, (a) => a.brand),
  ColumnDef('model', 'Modelo', 150, (a) => a.model),
  ColumnDef('serial', 'S/N', 150, (a) => _s(a.serialNumber)),
  ColumnDef('location', 'Ubicación', 190, (a) => _s(a.location)),
  ColumnDef('assigned', 'Responsable', 170, (a) => _s(a.assignedTo)),
  ColumnDef('quantity', 'Cantidad', 100, (a) => '${a.quantity} ${a.unit}'),
  ColumnDef('status', 'Estado', 140, (a) => _s(a.status)),
  ColumnDef('created', 'Registrado', 120, (a) => a.createdAt.toString().substring(0, 10)),
  ColumnDef('purchase', 'Fecha compra', 120, (a) => _d(a.purchaseDate)),
  ColumnDef('cost', 'Costo', 100, (a) => a.cost == null ? '—' : '\$${a.cost!.toStringAsFixed(2)}'),
  ColumnDef('supplier', 'Proveedor', 150, (a) => _s(a.supplier)),
  ColumnDef('invoice', 'Factura', 120, (a) => _s(a.invoiceNumber)),
  ColumnDef('warranty', 'Garantía hasta', 130, (a) => _d(a.warrantyUntil)),
  ColumnDef('notes', 'Notas', 240, (a) => _s(a.notes)),
];

const kDefaultColumns = ['asset', 'equipo', 'category', 'location', 'assigned', 'quantity', 'status'];

/// Columnas base + una por cada dato técnico que exista (IP, MAC, RAM...).
List<ColumnDef> allColumns(Iterable<ItAsset> items) {
  final keys = <String>{for (final a in items) ...a.specs.keys}.toList()..sort();
  return [
    ...kBaseColumns,
    for (final k in keys) ColumnDef('spec:$k', k, 140, (a) => _s(a.specs[k])),
  ];
}

class SavedColumns {
  final String name;
  final List<String> ids;
  const SavedColumns(this.name, this.ids);
  Map<String, dynamic> toJson() => {'name': name, 'ids': ids};
  factory SavedColumns.fromJson(Map<String, dynamic> j) =>
      SavedColumns(j['name'] as String, List<String>.from(j['ids'] as List));
}

class ColumnsState {
  final List<String> visible;
  final List<SavedColumns> saved;
  const ColumnsState(this.visible, this.saved);
}

class ColumnsNotifier extends StateNotifier<ColumnsState> {
  ColumnsNotifier() : super(const ColumnsState(kDefaultColumns, [])) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final vis = p.getStringList('cols_visible');
      final raw = p.getString('cols_saved');
      final saved = raw == null
          ? <SavedColumns>[]
          : (jsonDecode(raw) as List).map((e) => SavedColumns.fromJson(e as Map<String, dynamic>)).toList();
      state = ColumnsState((vis == null || vis.isEmpty) ? kDefaultColumns : vis, saved);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('cols_visible', state.visible);
      await p.setString('cols_saved', jsonEncode(state.saved.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> setVisible(List<String> ids) async {
    state = ColumnsState(ids.isEmpty ? kDefaultColumns : ids, state.saved);
    await _persist();
  }

  Future<void> saveAs(String name, List<String> ids) async {
    final rest = state.saved.where((s) => s.name != name).toList();
    state = ColumnsState(state.visible, [...rest, SavedColumns(name, ids)]);
    await _persist();
  }

  Future<void> removeSaved(String name) async {
    state = ColumnsState(state.visible, state.saved.where((s) => s.name != name).toList());
    await _persist();
  }
}

final columnsProvider = StateNotifierProvider<ColumnsNotifier, ColumnsState>((ref) => ColumnsNotifier());

/// Tags de los activos seleccionados en la lista.
final selectionProvider = StateProvider<Set<String>>((ref) => <String>{});
