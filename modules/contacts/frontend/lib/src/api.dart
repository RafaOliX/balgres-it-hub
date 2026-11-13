import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';

import 'models.dart';

class ContactsApi {
  // Se inyectan en build: --dart-define=API_USER=xxx --dart-define=API_PASS=yyy
  // En Web NO hace falta: el navegador ya maneja el basic auth de Caddy.
  static const _user = String.fromEnvironment('API_USER');
  static const _pass = String.fromEnvironment('API_PASS');

  final Dio _dio;

  ContactsApi({required String baseUrl})
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

  Future<List<Employee>> getEmpleados() async {
    final r = await _dio.get<List<dynamic>>('/contacts/employees/overview');
    return (r.data ?? []).map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Employee> getEmpleado(int id) async {
    final r = await _dio.get<Map<String, dynamic>>('/contacts/employees/$id');
    return Employee.fromJson(r.data!);
  }

  Future<void> crearEmpleado(Map<String, dynamic> body) async => await _dio.post('/contacts/employees', data: body);
  Future<void> actualizarEmpleado(int id, Map<String, dynamic> body) async => await _dio.put('/contacts/employees/$id', data: body);
  Future<void> eliminarEmpleado(int id) async => await _dio.delete('/contacts/employees/$id');

  Future<void> descargarEmpleadosExcel() async {
    final r = await _dio.get<List<int>>('/contacts/employees/export', options: Options(responseType: ResponseType.bytes));
    await FileSaver.instance.saveFile(name: 'empleados', bytes: Uint8List.fromList(r.data!), ext: 'xlsx', mimeType: MimeType.microsoftExcel);
  }

  Future<List<Location>> getUbicaciones() async {
    final r = await _dio.get<List<dynamic>>('/contacts/locations');
    return (r.data ?? []).map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
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
