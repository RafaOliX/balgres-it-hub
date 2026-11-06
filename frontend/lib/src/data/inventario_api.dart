import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
import '../models/category.dart';

class InventarioApi {
  final Dio _dio;

  InventarioApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic ${base64Encode(utf8.encode('admin:Balgres2026!'))}',
          },
        ));

  Future<List<Category>> getCategorias() async {
    final r = await _dio.get<List<dynamic>>('/inventario/categories');
    return (r.data ?? []).map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Category> crearCategoria(Category cat) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/categories', data: cat.toJson());
    return Category.fromJson(r.data!);
  }

  Future<Category> actualizarCategoria(int id, Category cat) async {
    final r = await _dio.put<Map<String, dynamic>>('/inventario/categories/$id', data: cat.toJson());
    return Category.fromJson(r.data!);
  }

  Future<void> eliminarCategoria(int id) async => await _dio.delete('/inventario/categories/$id');

  Future<List<ItAsset>> listar() async {
    final r = await _dio.get<List<dynamic>>('/inventario/');
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ItAsset>> buscar(String q) async {
    final r = await _dio.get<List<dynamic>>('/inventario/buscar', queryParameters: {'q': q});
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> getSiguienteTag(int categoryId) async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/siguiente-tag', queryParameters: {'category_id': categoryId});
    return r.data!['tag'] as String;
  }

  Future<ItAsset> crear(ItAssetCreate payload) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/', data: payload.toJson());
    return ItAsset.fromJson(r.data!);
  }

  Future<ItAsset> actualizar(String currentTag, Map<String, dynamic> body) async {
    final r = await _dio.patch<Map<String, dynamic>>('/inventario/$currentTag', data: body);
    return ItAsset.fromJson(r.data!);
  }

  Future<List<ItAssetHistory>> getHistorial(String tag) async {
    final r = await _dio.get<List<dynamic>>('/inventario/$tag/history');
    return (r.data ?? []).map((e) => ItAssetHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> eliminar(String tag) async => await _dio.delete<void>('/inventario/$tag');

  Future<List<ItAssetImage>> subirImagenes(String tag, List<XFile> files) async {
    final parts = <MultipartFile>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final mime = f.mimeType ?? 'image/jpeg';
      parts.add(MultipartFile.fromBytes(bytes, filename: f.name, contentType: DioMediaType.parse(mime)));
    }
    final form = FormData.fromMap({'files': parts});
    final r = await _dio.post<List<dynamic>>('/inventario/$tag/images', data: form, options: Options(contentType: 'multipart/form-data'));
    return (r.data ?? []).map((e) => ItAssetImage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> eliminarImagen(String tag, int imageId) async => await _dio.delete<void>('/inventario/$tag/images/$imageId');

  Future<void> importarExcel(Uint8List bytes) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: 'import.xlsx')});
    await _dio.post('/inventario/import', data: form, options: Options(contentType: 'multipart/form-data'));
  }

  // --- DESCARGAS ---
  Future<void> descargarExcel() async {
    final r = await _dio.get<List<int>>('/inventario/export', options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: 'inventario',
      bytes: Uint8List.fromList(r.data!),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> descargarPdf(String tag) async {
    final r = await _dio.get<List<int>>('/inventario/$tag/pdf', options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: 'acta_$tag',
      bytes: Uint8List.fromList(r.data!),
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}
