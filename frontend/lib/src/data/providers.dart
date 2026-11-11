import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/it_asset.dart';
import '../models/category.dart';
import 'inventario_api.dart';
import 'filters.dart';
import '../models/catalogs.dart';

final inventarioApiProvider = Provider<InventarioApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

// Provider para saber el host base (ej: 'http://192.168.0.10:8091' o '')
final appHostBaseProvider = Provider<String>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

final inventarioQueryProvider = StateProvider<String>((ref) => '');

final inventarioListProvider = FutureProvider.autoDispose<List<ItAsset>>((ref) async {
  final api = ref.watch(inventarioApiProvider);
  final q = ref.watch(inventarioQueryProvider);
  return q.isEmpty ? api.listar() : api.buscar(q);
});

final categoriasListProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  return ref.watch(inventarioApiProvider).getCategorias();
});


// Guarda los datos del formulario temporalmente
class AssetDraft {
  final String tag;
  final String brand;
  final String model;
  final String serial;
  final String location;
  final String assignedTo;
  final String notes;
  final String quantity;
  final String unit;
  final String status;
  final int? categoryId;
  final String categoryName;

  AssetDraft({
    this.tag = '', this.brand = '', this.model = '', this.serial = '',
    this.location = '', this.assignedTo = '', this.notes = '',
    this.quantity = '1', this.unit = 'Unidad', this.status = 'Operativo',
    this.categoryId, this.categoryName = '',
  });
}

final assetDraftProvider = StateProvider<AssetDraft>((ref) => AssetDraft());

final ubicacionesProvider = FutureProvider.autoDispose<List<Location>>((ref) async {
  return ref.watch(inventarioApiProvider).getUbicaciones();
});

final empleadosProvider = FutureProvider.autoDispose<List<Employee>>((ref) async {
  return ref.watch(inventarioApiProvider).getEmpleados();
});

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(inventarioApiProvider).getDashboard();
});

final actaTemplatesProvider = FutureProvider.autoDispose<List<ActaTemplate>>((ref) async {
  return ref.watch(inventarioApiProvider).getActaTemplates();
});

// ---------------------------------------------------------------- sugerencias de lo ya registrado
List<String> _rank(Iterable<String?> values) {
  final spell = <String, Map<String, int>>{};
  for (final v in values) {
    final t = (v ?? '').trim();
    if (t.isEmpty) continue;
    final m = spell.putIfAbsent(t.toLowerCase(), () => <String, int>{});
    m[t] = (m[t] ?? 0) + 1;
  }
  final ranked = spell.values.map((m) {
    final best = m.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return (best, m.values.fold<int>(0, (a, b) => a + b));
  }).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final r in ranked) r.$1];
}

class Hints {
  final List<String> brands, models;
  final Map<String, List<String>> _byBrand;
  final Map<String, List<String>> specs;
  const Hints(this.brands, this.models, this._byBrand, this.specs);

  /// Modelos de esa marca; si no hay, todos.
  List<String> modelsFor(String brand) {
    final k = brand.trim().toLowerCase();
    if (k.isEmpty) return models;
    final l = _byBrand[k];
    return (l == null || l.isEmpty) ? models : l;
  }
}

/// Marcas, modelos, proveedores y valores técnicos más usados (ordenados por frecuencia).
final hintsProvider = Provider.autoDispose<Hints>((ref) {
  final items = ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
  final grouped = <String, List<String>>{};
  final specVals = <String, List<String>>{};
  for (final a in items) {
    grouped.putIfAbsent(a.brand.trim().toLowerCase(), () => []).add(a.model);
    a.specs.forEach((k, v) => specVals.putIfAbsent(k, () => []).add(v));
  }
  return Hints(
    _rank(items.map((a) => a.brand)),
    _rank(items.map((a) => a.model)),
    {for (final e in grouped.entries) e.key: _rank(e.value)},
    {for (final e in specVals.entries) e.key: _rank(e.value)},
  );
});


/// Lista filtrada y ordenada: se calcula una vez por cambio de datos o de filtro.
final filteredAssetsProvider = Provider.autoDispose<List<ItAsset>>((ref) {
  final items = ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
  return applyFilter(items, ref.watch(inventoryFilterProvider));
});

/// Igual pero sin aplicar estado: alimenta los contadores de las pestañas.
final statusBaseProvider = Provider.autoDispose<List<ItAsset>>((ref) {
  final items = ref.watch(inventarioListProvider).valueOrNull ?? const <ItAsset>[];
  return applyFilter(items, ref.watch(inventoryFilterProvider), ignoreStatus: true);
});
