import 'dart:typed_data';

import 'package:balgres_it_ui/auth_session.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:file_saver/file_saver.dart';

import 'models.dart';

class TicketsApi {
  final Dio _dio;

  TicketsApi({required String baseUrl})
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

  Future<List<Ticket>> listar({String q = '', String? status, String? priority, bool abiertos = false, bool mios = false, String? assetTag, int? requesterId}) async {
    final r = await _dio.get<List<dynamic>>('/tickets/', queryParameters: {
      if (q.isNotEmpty) 'q': q,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (abiertos) 'abiertos': true,
      if (mios) 'mios': true,
      if (assetTag != null) 'asset_tag': assetTag,
      if (requesterId != null) 'requester_id': requesterId,
    });
    return (r.data ?? []).map((e) => Ticket.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> resumen() async => (await _dio.get<Map<String, dynamic>>('/tickets/resumen')).data ?? {};

  Future<List<TicketUser>> usuarios() async {
    final r = await _dio.get<List<dynamic>>('/tickets/usuarios');
    return (r.data ?? []).map((e) => TicketUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Ticket> obtener(int id) async => Ticket.fromJson((await _dio.get<Map<String, dynamic>>('/tickets/$id')).data!);
  Future<Ticket> crear(Map<String, dynamic> body) async => Ticket.fromJson((await _dio.post<Map<String, dynamic>>('/tickets/', data: body)).data!);
  Future<Ticket> actualizar(int id, Map<String, dynamic> body) async => Ticket.fromJson((await _dio.put<Map<String, dynamic>>('/tickets/$id', data: body)).data!);
  Future<void> eliminar(int id) async => await _dio.delete('/tickets/$id');

  Future<void> comentar(int id, String body) async => await _dio.post('/tickets/$id/comentarios', data: {'body': body});
  Future<void> borrarComentario(int id, int cid) async => await _dio.delete('/tickets/$id/comentarios/$cid');

  Future<void> subirArchivos(int id, List<PlatformFile> files) async {
    final form = FormData.fromMap({'files': [for (final f in files) MultipartFile.fromBytes(f.bytes!, filename: f.name)]});
    await _dio.post('/tickets/$id/archivos', data: form, options: Options(contentType: 'multipart/form-data', sendTimeout: const Duration(minutes: 10)));
  }

  Future<void> descargarArchivo(int id, TicketArchivo a) async {
    final r = await _dio.get<List<int>>('/tickets/$id/archivos/${a.id}/download', options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 10)));
    final dot = a.name.lastIndexOf('.');
    await FileSaver.instance.saveFile(
      name: dot > 0 ? a.name.substring(0, dot) : a.name,
      bytes: Uint8List.fromList(r.data!),
      ext: dot > 0 ? a.name.substring(dot + 1) : '',
      mimeType: MimeType.other,
    );
  }

  Future<void> eliminarArchivo(int id, int aid) async => await _dio.delete('/tickets/$id/archivos/$aid');
}
