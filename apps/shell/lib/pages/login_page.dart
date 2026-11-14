import 'package:balgres_it_inventario/balgres_it_inventario.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../core/brand.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _show = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Escribe tu usuario y contraseña');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).login(_user.text.trim(), _pass.text);
    if (mounted) setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: cardDeco(context, radius: 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: BrandLogo(height: 56)),
                const SizedBox(height: 22),
                const Text('Iniciar sesión', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                const SizedBox(height: 4),
                Text('Balgres IT Hub', style: TextStyle(fontSize: 13, color: c.muted)),
                const SizedBox(height: 22),
                TextField(controller: _user, autofocus: true, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Usuario')),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: !_show,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _show = !_show)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.bad.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.bad)),
                    child: Text(_error!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Entrando…' : 'Entrar'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cambio de contraseña: obligatorio en el primer ingreso o tras un reseteo, voluntario desde el menú.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _rep = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _rep.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_new.text.length < 8) {
      setState(() => _error = 'La contraseña nueva debe tener al menos 8 caracteres');
      return;
    }
    if (_new.text != _rep.text) {
      setState(() => _error = 'La confirmación no coincide');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).changePassword(_cur.text, _new.text);
      await ref.read(authProvider.notifier).refresh();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final forced = ref.watch(authProvider).user?.mustChangePassword ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar contraseña'),
        actions: [
          if (forced) TextButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: const Text('Cerrar sesión')),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: cardDeco(context),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (forced) ...[
                  Text('Por seguridad debes definir una contraseña propia antes de continuar.', style: TextStyle(color: c.muted, fontSize: 13)),
                  const SizedBox(height: 16),
                ],
                TextField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
                const SizedBox(height: 14),
                TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña nueva', helperText: 'Mínimo 8 caracteres')),
                const SizedBox(height: 14),
                TextField(controller: _rep, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Repite la contraseña nueva')),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Guardando…' : 'Guardar'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
