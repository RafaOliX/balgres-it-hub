import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
import '../models/category.dart';
import '../models/catalogs.dart';

class InventarioApi {
  // Se inyectan en build: --dart-define=API_USER=xxx --dart-define=API_PASS=yyy
  // En Web NO hace falta: el navegador ya maneja el basic auth de Caddy.
  static const _user = String.fromEnvironment('API_USER');
  static const _pass = String.fromEnvironment('API_PASS');

  final Dio _dio;

  InventarioApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            if (_user.isNotEmpty)
              'Authorization': 'Basic ${base64Encode(utf8.encode('$_user:$_pass'))}',
          },
        ));

  // ---- Categorías
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

  // ---- Activos
  Future<List<ItAsset>> listar() async {
    final r = await _dio.get<List<dynamic>>('/inventario/');
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ItAsset>> buscar(String q) async {
    final r = await _dio.get<List<dynamic>>('/inventario/buscar', queryParameters: {'q': q});
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ItAsset> obtener(String tag) async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/$tag');
    return ItAsset.fromJson(r.data!);
  }

  Future<Map<String, dynamic>> getStats() async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/stats');
    return r.data!;
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

  Future<void> ajustarStock(String tag, int amount) async {
    await _dio.post('/inventario/$tag/adjust-stock', queryParameters: {'amount': amount});
  }

  // ---- Imágenes
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

  // ---- Excel / PDF
  /// Devuelve {creados, omitidos, errores:[{fila, detalle}]}
  Future<Map<String, dynamic>> importarExcel(Uint8List bytes) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: 'import.xlsx')});
    final r = await _dio.post<Map<String, dynamic>>('/inventario/import', data: form, options: Options(contentType: 'multipart/form-data'));
    return r.data ?? {};
  }

  Future<void> descargarExcel() async {
    final r = await _dio.get<List<int>>('/inventario/export', options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: 'inventario',
      bytes: Uint8List.fromList(r.data!),
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> descargarPdf(String tag) async {
    final r = await _dio.get<List<int>>('/inventario/$tag/pdf', options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: 'acta_$tag',
      bytes: Uint8List.fromList(r.data!),
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  // ---- Ubicaciones
  Future<List<Location>> getUbicaciones() async {
    final r = await _dio.get<List<dynamic>>('/inventario/locations');
    return (r.data ?? []).map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> crearUbicacion(Map<String, dynamic> body) async => await _dio.post('/inventario/locations', data: body);
  Future<void> actualizarUbicacion(int id, Map<String, dynamic> body) async => await _dio.put('/inventario/locations/$id', data: body);
  Future<void> eliminarUbicacion(int id) async => await _dio.delete('/inventario/locations/$id');

  Future<Map<String, dynamic>> importarUbicaciones() async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/locations/import-from-assets');
    return r.data ?? {};
  }

  // ---- Empleados
  Future<List<Employee>> getEmpleados() async {
    final r = await _dio.get<List<dynamic>>('/inventario/employees');
    return (r.data ?? []).map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> crearEmpleado(Map<String, dynamic> body) async => await _dio.post('/inventario/employees', data: body);
  Future<void> actualizarEmpleado(int id, Map<String, dynamic> body) async => await _dio.put('/inventario/employees/$id', data: body);
  Future<void> eliminarEmpleado(int id) async => await _dio.delete('/inventario/employees/$id');

  Future<Map<String, dynamic>> importarEmpleados() async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/employees/import-from-assets');
    return r.data ?? {};
  }

  // ---- Asignaciones
  Future<List<Assignment>> getAsignaciones(String tag) async {
    final r = await _dio.get<List<dynamic>>('/inventario/$tag/assignments');
    return (r.data ?? []).map((e) => Assignment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> asignar(String tag, int employeeId, String notes) async =>
      await _dio.post('/inventario/$tag/assign', data: {'employee_id': employeeId, 'notes': notes.isEmpty ? null : notes});

  Future<void> devolver(String tag, String notes) async =>
      await _dio.post('/inventario/$tag/return', data: {'notes': notes.isEmpty ? null : notes});

  // ---- Dashboard / papelera / etiquetas
  Future<Map<String, dynamic>> getDashboard() async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/dashboard');
    return r.data ?? {};
  }

  Future<List<ItAsset>> getPapelera() async {
    final r = await _dio.get<List<dynamic>>('/inventario/papelera');
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> restaurar(String tag) async => await _dio.post('/inventario/$tag/restore');
  Future<void> purgar(String tag) async => await _dio.delete('/inventario/$tag/purge');

  Future<void> descargarEtiquetas([List<String>? tags]) async {
    final r = await _dio.get<List<int>>(
      '/inventario/labels',
      queryParameters: tags == null ? null : {'tags': tags.join(',')},
      options: Options(responseType: ResponseType.bytes),
    );
    await FileSaver.instance.saveFile(name: 'etiquetas', bytes: Uint8List.fromList(r.data!), ext: 'pdf', mimeType: MimeType.pdf);
  }
}

/// Extrae el mensaje 'detail' que devuelve FastAPI.
String apiError(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['detail'] != null) {
      final det = d['detail'];
      if (det is List) return det.map((x) => x is Map ? (x['msg'] ?? x).toString() : x.toString()).join('; ');
      return det.toString();
    }
    return e.message ?? 'Error de red';
  }
  return e.toString();
}
