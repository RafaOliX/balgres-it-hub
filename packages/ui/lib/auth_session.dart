/// Sesión en memoria compartida por todos los módulos. El shell la llena al iniciar sesión.
class AuthSession {
  static String? token;
  static Set<String> permissions = {};
  static void Function()? onUnauthorized;

  static bool can(String perm) => permissions.contains('*') || permissions.contains(perm);

  static void clear() {
    token = null;
    permissions = {};
  }
}
