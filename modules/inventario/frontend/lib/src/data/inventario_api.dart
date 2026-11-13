import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
import '../models/category.dart';
import '../models/catalogs.dart';

export 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;

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

  /// Huella barata del inventario: solo se recarga la lista si cambia.
  Future<String> getVersion() async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/version');
    return (r.data?['v'] ?? '').toString();
  }

  Future<Map<String, dynamic>> getStats() async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/stats');
    return r.data!;
  }

  Future<String> getSiguienteTag(int categoryId) async {
    final r = await _dio.get<Map<String, dynamic>>('/inventario/siguiente-tag', queryParameters: {'category_id': categoryId});
    return r.data!['tag'] as String;
  }

  Future<ItAsset> crear(ItAssetCreate payload, {bool autoTag = false}) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/',
        data: payload.toJson(), queryParameters: autoTag ? {'auto_tag': true} : null);
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

  Future<void> descargarPdf(String tag, {int? templateId}) async {
    final r = await _dio.get<List<int>>('/inventario/$tag/pdf',
        queryParameters: templateId == null ? null : {'template_id': templateId},
        options: Options(responseType: ResponseType.bytes));
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

  Future<int> limpiarBorradores({int dias = 7}) async {
    final r = await _dio.delete<Map<String, dynamic>>('/inventario/borradores', queryParameters: {'dias': dias});
    return (r.data?['eliminados'] as num?)?.toInt() ?? 0;
  }

  Future<List<ItAsset>> getEmpleadoActivos(int id) async {
    final r = await _dio.get<List<dynamic>>('/inventario/employees/$id/assets');
    return (r.data ?? []).map((e) => ItAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getEmpleadoHistorial(int id) async {
    final r = await _dio.get<List<dynamic>>('/inventario/employees/$id/history');
    return (r.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> descargarActaEmpleado(int id, String name, {int? templateId}) async {
    final r = await _dio.get<List<int>>('/inventario/employees/$id/pdf',
        queryParameters: templateId == null ? null : {'template_id': templateId},
        options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: 'acta_${name.replaceAll(' ', '_')}',
      bytes: Uint8List.fromList(r.data!),
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  // ---- plantillas de acta
  Future<List<ActaTemplate>> getActaTemplates() async {
    final r = await _dio.get<List<dynamic>>('/inventario/acta-templates');
    return (r.data ?? []).map((e) => ActaTemplate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ActaTemplate> crearActaTemplate(String name, Map<String, dynamic> config) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/acta-templates', data: {'name': name, 'config': config});
    return ActaTemplate.fromJson(r.data!);
  }

  Future<ActaTemplate> actualizarActaTemplate(int id, String name, Map<String, dynamic> config) async {
    final r = await _dio.put<Map<String, dynamic>>('/inventario/acta-templates/$id', data: {'name': name, 'config': config});
    return ActaTemplate.fromJson(r.data!);
  }

  Future<void> eliminarActaTemplate(int id) async => await _dio.delete('/inventario/acta-templates/$id');

  /// Sin empleado = hoja en blanco. [blank] deja la tabla vacía para escribir a mano.
  Future<void> descargarActaPlantilla(int id, {int? employeeId, List<String>? tags, bool blank = false, String name = 'plantilla'}) async {
    final r = await _dio.get<List<int>>('/inventario/acta-templates/$id/pdf',
        queryParameters: {
          if (employeeId != null) 'employee_id': employeeId,
          if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
          if (blank) 'blank': true,
        },
        options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(
      name: name.replaceAll(' ', '_'), bytes: Uint8List.fromList(r.data!), ext: 'pdf', mimeType: MimeType.pdf);
  }

  // ---- empleados: baja, traspaso y exportación
  Future<int> bajaEmpleado(int id, String notes) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/employees/$id/offboard', data: {'notes': notes.isEmpty ? null : notes});
    return (r.data?['devueltos'] as num?)?.toInt() ?? 0;
  }

  Future<int> traspasarEmpleado(int id, int toId, String notes) async {
    final r = await _dio.post<Map<String, dynamic>>('/inventario/employees/$id/transfer',
        data: {'to_employee_id': toId, 'notes': notes.isEmpty ? null : notes});
    return (r.data?['traspasados'] as num?)?.toInt() ?? 0;
  }

  Future<void> descargarEtiquetas([List<String>? tags]) async {
    final r = await _dio.get<List<int>>(
      '/inventario/labels',
      queryParameters: tags == null ? null : {'tags': tags.join(',')},
      options: Options(responseType: ResponseType.bytes),
    );
    await FileSaver.instance.saveFile(name: 'etiquetas', bytes: Uint8List.fromList(r.data!), ext: 'pdf', mimeType: MimeType.pdf);
  }
}
