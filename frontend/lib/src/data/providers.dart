import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/it_asset.dart';
import '../models/category.dart';
import 'inventario_api.dart';

final inventarioApiProvider = Provider<InventarioApi>((ref) {
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
