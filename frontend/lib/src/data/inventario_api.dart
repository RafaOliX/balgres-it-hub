import 'package:dio/dio.dart';

import '../models/it_asset.dart';

class InventarioApi {
  final Dio _dio;

  InventarioApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Content-Type': 'application/json'},
        ));

  Future<List<ItAsset>> listar() async {
    final r = await _dio.get<List<dynamic>>('/inventario/');
    return (r.data ?? [])
        .map((e) => ItAsset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ItAsset>> buscar(String q) async {
    final r = await _dio.get<List<dynamic>>(
      '/inventario/buscar',
      queryParameters: {'q': q},
    );
    return (r.data ?? [])
        .map((e) => ItAsset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ItAsset> crear(ItAssetCreate payload) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/inventario/',
      data: payload.toJson(),
    );
    return ItAsset.fromJson(r.data!);
  }

  Future<ItAsset> actualizar(
    String tag, {
    String? status,
    String? location,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      if (status != null) 'status': status,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
    };
    final r = await _dio.patch<Map<String, dynamic>>(
      '/inventario/$tag',
      data: body,
    );
    return ItAsset.fromJson(r.data!);
  }

  Future<void> eliminar(String tag) async {
    await _dio.delete<void>('/inventario/$tag');
  }
}
