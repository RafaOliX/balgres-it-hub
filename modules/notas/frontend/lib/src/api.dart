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

  Future<void> crear(Map<String, dynamic> body) async => await _dio.post('/notas/', data: body);
  Future<void> actualizar(int id, Map<String, dynamic> body) async => await _dio.put('/notas/$id', data: body);
  Future<void> eliminar(int id) async => await _dio.delete('/notas/$id');
}
