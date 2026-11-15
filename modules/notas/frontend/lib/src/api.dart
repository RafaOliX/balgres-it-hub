import 'package:dio/dio.dart';
import 'package:balgres_it_ui/auth_session.dart';

import 'models.dart';

class NotasApi {
  final Dio _dio;

  NotasApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
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

  Future<List<Nota>> listar({String q = '', String? tag}) async {
    final r = await _dio.get<List<dynamic>>('/notas/', queryParameters: {
      if (q.isNotEmpty) 'q': q,
      if (tag != null) 'tag': tag,
    });
    return (r.data ?? []).map((e) => Nota.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TagCount>> getTags() async {
    final r = await _dio.get<List<dynamic>>('/notas/tags');
    return (r.data ?? []).map((e) => TagCount.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Nota> obtener(int id) async {
    final r = await _dio.get<Map<String, dynamic>>('/notas/$id');
    return Nota.fromJson(r.data!);
  }

  Future<Nota> crear(Map<String, dynamic> body) async {
    final r = await _dio.post<Map<String, dynamic>>('/notas/', data: body);
    return Nota.fromJson(r.data!);
  }

  Future<void> actualizar(int id, Map<String, dynamic> body) async => await _dio.put('/notas/$id', data: body);
  Future<void> eliminar(int id) async => await _dio.delete('/notas/$id');

  /// Planos que enlazan a esta nota (los sirve el módulo planos). Sin permiso o sin módulo: lista vacía.
  Future<List<Map<String, dynamic>>> planosVinculados(int id) async {
    try {
      final r = await _dio.get<List<dynamic>>('/planos/by-nota/$id');
      return (r.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  // ---- diagramas (draw.io)
  Future<List<NotaDiagrama>> listarDiagramas(int notaId) async {
    final r = await _dio.get<List<dynamic>>('/notas/$notaId/diagramas');
    return (r.data ?? []).map((e) => NotaDiagrama.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<NotaDiagrama> obtenerDiagrama(int notaId, int id) async {
    final r = await _dio.get<Map<String, dynamic>>('/notas/$notaId/diagramas/$id');
    return NotaDiagrama.fromJson(r.data!);
  }

  Future<NotaDiagrama> crearDiagrama(int notaId, String title, String xml) async {
    final r = await _dio.post<Map<String, dynamic>>('/notas/$notaId/diagramas', data: {'title': title, 'xml': xml});
    return NotaDiagrama.fromJson(r.data!);
  }

  Future<void> actualizarDiagrama(int notaId, int id, String title, String xml) async =>
      await _dio.put('/notas/$notaId/diagramas/$id', data: {'title': title, 'xml': xml});

  Future<void> eliminarDiagrama(int notaId, int id) async => await _dio.delete('/notas/$notaId/diagramas/$id');
}
