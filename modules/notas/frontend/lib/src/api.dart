import 'dart:typed_data';

import 'package:balgres_it_ui/auth_session.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:file_saver/file_saver.dart';

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

  Future<Nota> actualizar(int id, Map<String, dynamic> body) async {
    final r = await _dio.put<Map<String, dynamic>>('/notas/$id', data: body);
    return Nota.fromJson(r.data!);
  }

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

  // ---- historial
  Future<List<NotaRevision>> historial(int id) async {
    final r = await _dio.get<List<dynamic>>('/notas/$id/historial');
    return (r.data ?? []).map((e) => NotaRevision.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<NotaRevision> version(int id, int rid) async {
    final r = await _dio.get<Map<String, dynamic>>('/notas/$id/historial/$rid');
    return NotaRevision.fromJson(r.data!);
  }

  Future<Nota> restaurar(int id, int rid) async {
    final r = await _dio.post<Map<String, dynamic>>('/notas/$id/historial/$rid/restore');
    return Nota.fromJson(r.data!);
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

  Future<NotaDiagrama> crearDiagrama(int notaId, String title, String xml, {String? preview}) async {
    final r = await _dio.post<Map<String, dynamic>>('/notas/$notaId/diagramas', data: {'title': title, 'xml': xml, 'preview': preview});
    return NotaDiagrama.fromJson(r.data!);
  }

  Future<void> actualizarDiagrama(int notaId, int id, String title, String xml, {String? preview}) async =>
      await _dio.put('/notas/$notaId/diagramas/$id', data: {'title': title, 'xml': xml, 'preview': preview});

  Future<void> eliminarDiagrama(int notaId, int id) async => await _dio.delete('/notas/$notaId/diagramas/$id');

  // ---- archivos adjuntos
  Future<List<NotaArchivo>> listarArchivos(int notaId) async {
    final r = await _dio.get<List<dynamic>>('/notas/$notaId/archivos');
    return (r.data ?? []).map((e) => NotaArchivo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> subirArchivos(int notaId, List<PlatformFile> files) async {
    final form = FormData.fromMap({
      'files': [for (final f in files) MultipartFile.fromBytes(f.bytes!, filename: f.name)],
    });
    await _dio.post('/notas/$notaId/archivos', data: form, options: Options(contentType: 'multipart/form-data', sendTimeout: const Duration(minutes: 10)));
  }

  Future<void> descargarArchivo(int notaId, NotaArchivo a) async {
    final r = await _dio.get<List<int>>('/notas/$notaId/archivos/${a.id}/download', options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 10)));
    final dot = a.name.lastIndexOf('.');
    await FileSaver.instance.saveFile(
      name: dot > 0 ? a.name.substring(0, dot) : a.name,
      bytes: Uint8List.fromList(r.data!),
      ext: dot > 0 ? a.name.substring(dot + 1) : '',
      mimeType: MimeType.other,
    );
  }

  Future<void> eliminarArchivo(int notaId, int id) async => await _dio.delete('/notas/$notaId/archivos/$id');
}
