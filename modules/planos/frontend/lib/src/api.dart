import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:balgres_it_ui/auth_session.dart';

import 'models.dart';

class PlanosApi {
  final Dio _dio;

  PlanosApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        final t = AuthSession.token;
        if (t != null) o.headers['Authorization'] = 'Bearer $t';
        h.next(o);
      },
      onError: (e, h) {
        if (e.response?.statusCode == 401 && AuthSession.token != null) AuthSession.onUnauthorized?.call();
        h.next(e);
      },
    ));
  }

  Future<List<Plano>> listar() async {
    final r = await _dio.get<List<dynamic>>('/planos/');
    return (r.data ?? []).map((e) => Plano.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Plano> obtener(int id) async {
    final r = await _dio.get<Map<String, dynamic>>('/planos/$id');
    return Plano.fromJson(r.data!);
  }

  Future<void> crear(String name, String notes, Uint8List bytes, String filename) async {
    final ext = filename.toLowerCase().split('.').last;
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    final form = FormData.fromMap({
      'name': name,
      'notes': notes,
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(mime)),
    });
    await _dio.post('/planos/', data: form, options: Options(contentType: 'multipart/form-data'));
  }

  Future<void> actualizar(int id, Map<String, dynamic> body) async => await _dio.put('/planos/$id', data: body);
  Future<void> eliminar(int id) async => await _dio.delete('/planos/$id');

  Future<void> crearPin(int planoId, Map<String, dynamic> body) async => await _dio.post('/planos/$planoId/pins', data: body);
  Future<void> actualizarPin(int planoId, int pinId, Map<String, dynamic> body) async => await _dio.put('/planos/$planoId/pins/$pinId', data: body);
  Future<void> eliminarPin(int planoId, int pinId) async => await _dio.delete('/planos/$planoId/pins/$pinId');

  Future<void> crearTrazo(int planoId, Map<String, dynamic> body) async => await _dio.post('/planos/$planoId/trazos', data: body);
  Future<void> eliminarTrazo(int planoId, int trazoId) async => await _dio.delete('/planos/$planoId/trazos/$trazoId');
  Future<void> limpiarTrazos(int planoId) async => await _dio.delete('/planos/$planoId/trazos');

  /// Notas disponibles para vincular (las sirve el módulo notas). Sin permiso o sin módulo: lista vacía.
  Future<List<NotaRef>> getNotas() async {
    try {
      final r = await _dio.get<List<dynamic>>('/notas/');
      return (r.data ?? []).map((e) => NotaRef.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}
