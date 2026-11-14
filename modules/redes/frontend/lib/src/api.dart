import 'dart:convert';
import 'package:dio/dio.dart';

import 'models.dart';

class RedesApi {
  // Se inyectan en build: --dart-define=API_USER=xxx --dart-define=API_PASS=yyy
  // En Web NO hace falta: el navegador ya maneja el basic auth de Caddy.
  static const _user = String.fromEnvironment('API_USER');
  static const _pass = String.fromEnvironment('API_PASS');

  final Dio _dio;

  RedesApi({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 120), // un barrido /22 puede tardar
          headers: {
            'Content-Type': 'application/json',
            if (_user.isNotEmpty) 'Authorization': 'Basic ${base64Encode(utf8.encode('$_user:$_pass'))}',
          },
        ));

  Future<List<IpEntry>> getIps() async {
    final r = await _dio.get<List<dynamic>>('/redes/ips');
    return (r.data ?? []).map((e) => IpEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> crearIp(Map<String, dynamic> body) async => await _dio.post('/redes/ips', data: body);
  Future<void> actualizarIp(int id, Map<String, dynamic> body) async => await _dio.put('/redes/ips/$id', data: body);
  Future<void> eliminarIp(int id) async => await _dio.delete('/redes/ips/$id');

  Future<List<Subnet>> getSubnets() async {
    final r = await _dio.get<List<dynamic>>('/redes/subnets');
    return (r.data ?? []).map((e) => Subnet.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> crearSubnet(String name, String cidr) async => await _dio.post('/redes/subnets', data: {'name': name, 'cidr': cidr});
  Future<void> eliminarSubnet(int id) async => await _dio.delete('/redes/subnets/$id');

  Future<List<Segment>> getSegmentos() async {
    final r = await _dio.get<List<dynamic>>('/redes/segments');
    return (r.data ?? []).map((e) => Segment.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Nombre vacío = quitar el nombre del segmento.
  Future<void> nombrarSegmento(String cidr, String name) async => await _dio.put('/redes/segments', data: {'cidr': cidr, 'name': name});

  Future<List<DuplicateIp>> getDuplicadas() async {
    final r = await _dio.get<List<dynamic>>('/redes/duplicates');
    return (r.data ?? []).map((e) => DuplicateIp.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> sincronizar() async {
    final r = await _dio.post<Map<String, dynamic>>('/redes/sync');
    return r.data ?? {};
  }

  /// [register] guarda como "escaneo" las IPs vivas que no estaban registradas.
  Future<Map<String, dynamic>> escanear(String cidr, {bool register = false}) async {
    final r = await _dio.post<Map<String, dynamic>>('/redes/scan', data: {'cidr': cidr, 'register': register});
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> verificarRegistradas() async {
    final r = await _dio.post<Map<String, dynamic>>('/redes/check-registered');
    return r.data ?? {};
  }
}
