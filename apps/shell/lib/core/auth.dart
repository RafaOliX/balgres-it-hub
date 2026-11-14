import 'package:balgres_it_inventario/balgres_it_inventario.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthUser {
  final int id;
  final String username, role;
  final String? fullName;
  final Set<String> permissions;
  final bool mustChangePassword;
  const AuthUser({required this.id, required this.username, required this.role, this.fullName, required this.permissions, required this.mustChangePassword});

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        username: j['username'] as String,
        fullName: j['full_name'] as String?,
        role: (j['role'] as String?) ?? '',
        permissions: {for (final p in (j['permissions'] as List? ?? const [])) p.toString()},
        mustChangePassword: j['must_change_password'] as bool? ?? false,
      );

  String get display => (fullName ?? '').trim().isEmpty ? username : fullName!;
  bool can(String perm) => permissions.contains('*') || permissions.contains(perm);
}

// ====================================================================== API
class AuthApi {
  final Dio _dio;

  AuthApi({required String baseUrl})
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

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final r = await _dio.get<List<dynamic>>(path);
    return (r.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> login(String user, String pass) async {
    final r = await _dio.post<Map<String, dynamic>>('/auth/login', data: {'username': user, 'password': pass});
    return r.data!;
  }

  Future<AuthUser> me() async => AuthUser.fromJson((await _dio.get<Map<String, dynamic>>('/auth/me')).data!);
  Future<void> logout() async => await _dio.post('/auth/logout');
  Future<void> changePassword(String current, String next) async =>
      await _dio.post('/auth/change-password', data: {'current_password': current, 'new_password': next});

  // ---- administración
  Future<Map<String, dynamic>> catalog() async => (await _dio.get<Map<String, dynamic>>('/auth/catalog')).data!;
  Future<List<Map<String, dynamic>>> roles() => _list('/auth/roles');
  Future<List<Map<String, dynamic>>> users() => _list('/auth/users');
  Future<void> crearRol(Map<String, dynamic> body) async => await _dio.post('/auth/roles', data: body);
  Future<void> actualizarRol(int id, Map<String, dynamic> body) async => await _dio.put('/auth/roles/$id', data: body);
  Future<void> eliminarRol(int id) async => await _dio.delete('/auth/roles/$id');
  Future<void> crearUsuario(Map<String, dynamic> body) async => await _dio.post('/auth/users', data: body);
  Future<void> actualizarUsuario(int id, Map<String, dynamic> body) async => await _dio.put('/auth/users/$id', data: body);
  Future<void> resetearClave(int id, String pass) async => await _dio.post('/auth/users/$id/reset-password', data: {'password': pass});
}

final authApiProvider = Provider<AuthApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

// ====================================================================== estado
class AuthState {
  final bool loading;
  final AuthUser? user;
  const AuthState({this.loading = true, this.user});
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _api;
  static const _key = 'auth_token';

  AuthNotifier(this._api) : super(const AuthState()) {
    AuthSession.onUnauthorized = _expired;
    _restore();
  }

  void _apply(AuthUser u) {
    AuthSession.permissions = u.permissions;
    state = AuthState(loading: false, user: u);
  }

  Future<void> _forget() async {
    AuthSession.clear();
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final t = (await SharedPreferences.getInstance()).getString(_key);
      if (t != null) {
        AuthSession.token = t;
        _apply(await _api.me());
        return;
      }
    } catch (e) {
      AuthSession.clear();
      if (e is DioException && e.response?.statusCode == 401) await _forget();
    }
    state = const AuthState(loading: false);
  }

  void _expired() {
    _forget();
    state = const AuthState(loading: false);
  }

  /// Devuelve null si entró, o el mensaje de error.
  Future<String?> login(String user, String pass) async {
    try {
      final j = await _api.login(user, pass);
      final token = j['token'] as String;
      AuthSession.token = token;
      try {
        await (await SharedPreferences.getInstance()).setString(_key, token);
      } catch (_) {}
      _apply(AuthUser.fromJson(j));
      return null;
    } catch (e) {
      return apiError(e);
    }
  }

  Future<void> refresh() async => _apply(await _api.me());

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {}
    await _forget();
    state = const AuthState(loading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref.watch(authApiProvider)));

// ====================================================================== menú de usuario
class UserMenuButton extends ConsumerWidget {
  const UserMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    if (u == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: u.display,
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) {
        if (v == 'pass') context.push('/cambiar-clave');
        if (v == 'out') ref.read(authProvider.notifier).logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(enabled: false, child: Text('${u.display} · ${u.role}')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'pass', child: Text('Cambiar contraseña')),
        const PopupMenuItem<String>(value: 'out', child: Text('Cerrar sesión')),
      ],
    );
  }
}
