import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/it_asset.dart';
import '../models/category.dart';
import 'inventario_api.dart';

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
    this.quantity = '1', this.unit = 'Unidad', this.status = 'Borrador',
    this.categoryId, this.categoryName = '',
  });
}

final assetDraftProvider = StateProvider<AssetDraft>((ref) => AssetDraft());
