import 'dart:async';

import 'package:balgres_it_ui/text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/catalogs.dart';
import '../ui/swiss.dart';
import 'search_select.dart';

class FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const FormSection(this.title, this.children, {super.key});

  @override
  Widget build(BuildContext context) => SwissSection(title, children);
}

/// Ubicación con búsqueda: escribe "rack" y trae "Informática › Sala › Rack 1".
class LocationDropdown extends ConsumerWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;
  const LocationDropdown({super.key, required this.value, required this.onChanged, this.label = 'Ubicación'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ubicacionesProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (locs) => SearchSelect<Location>(
        label: label,
        value: locs.where((l) => l.id == value).firstOrNull,
        options: locs,
        display: (l) => l.fullName,
        subtitle: (l) => l.kind ?? '',
        hint: 'Escribe para buscar: Informática, rack…',
        onChanged: (l) => onChanged(l?.id),
      ),
    );
  }
}

const _ipKeys = {'ip', 'direccion ip', 'direccion de ip', 'dir ip', 'ip address', 'ip addr', 'ipv4', 'ip v4'};

/// Mismo criterio que el backend (redes/service.py): sin tildes ni mayúsculas.
bool isIpSpecKey(String k) {
  final n = normalizeText(k).replaceAll(RegExp(r'[._-]'), ' ').trim().split(RegExp(r'\s+')).join(' ');
  return _ipKeys.contains(n);
}

class SpecsFields extends StatelessWidget {
  final Map<String, TextEditingController> ctrls;
  final Map<String, List<String>> hints;
  /// Tag del activo (si ya existe) para que su propia IP no cuente como "en uso".
  final String? assetTag;
  const SpecsFields({super.key, required this.ctrls, this.hints = const {}, this.assetTag});

  @override
  Widget build(BuildContext context) {
    if (ctrls.isEmpty) {
      return Text('Esta categoría no tiene campos técnicos. Puedes definirlos en Categorías.', style: TextStyle(color: context.sw.muted, fontSize: 13));
    }
    return Wrap(
      spacing: 16, runSpacing: 16,
      children: ctrls.entries
          .map((e) => SizedBox(
                key: ValueKey('spec:${e.key}'),
                width: 240,
                child: isIpSpecKey(e.key)
                    ? IpSpecField(controller: e.value, label: e.key, assetTag: assetTag, suggestions: () => hints[e.key] ?? const [])
                    : SuggestField(controller: e.value, label: e.key, suggestions: () => hints[e.key] ?? const []),
              ))
          .toList(),
    );
  }
}

/// Campo de IP con validación en vivo contra Redes: libre, en uso (y por quién) o no válida.
class IpSpecField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? assetTag;
  final List<String> Function() suggestions;
  const IpSpecField({super.key, required this.controller, required this.label, required this.suggestions, this.assetTag});

  @override
  ConsumerState<IpSpecField> createState() => _IpSpecFieldState();
}

class _IpSpecFieldState extends ConsumerState<IpSpecField> {
  Timer? _timer;
  String _last = '';
  String? _msg;
  int _level = 0; // 0 correcto, 1 aviso, 2 error

  @override
  void initState() {
    super.initState();
    _last = widget.controller.text.trim();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant IpSpecField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _last = widget.controller.text.trim();
      _msg = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final v = widget.controller.text.trim();
    if (v == _last) return;
    _last = v;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: v.isEmpty ? 0 : 500), () => _check(v));
  }

  Future<void> _check(String v) async {
    if (!mounted) return;
    if (v.isEmpty) {
      setState(() => _msg = null);
      return;
    }
    try {
      final r = await ref.read(inventarioApiProvider).verificarIp(v, assetTag: widget.assetTag);
      if (!mounted || widget.controller.text.trim() != v) return;
      setState(() {
        if (r['valida'] == false) {
          _msg = 'No es una IP válida: se guardará, pero no se reservará.';
          _level = 1;
        } else if (r['libre'] == false) {
          _msg = 'En uso por ${r['usada_por']}.';
          _level = 2;
        } else if (r['vincular'] != null) {
          _msg = 'Registrada en Redes como "${r['vincular']}": se vinculará a este activo.';
          _level = 0;
        } else {
          _msg = 'IP disponible.';
          _level = 0;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _msg = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final col = _level == 2 ? c.bad : (_level == 1 ? c.warn : c.ok);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SuggestField(controller: widget.controller, label: widget.label, suggestions: widget.suggestions),
      if (_msg != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(_msg!, style: TextStyle(fontSize: 12, color: col, fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

Map<String, String> collectSpecs(Map<String, TextEditingController> ctrls) {
  final m = <String, String>{};
  ctrls.forEach((k, c) {
    final t = c.text.trim();
    if (t.isNotEmpty) m[k] = t;
  });
  return m;
}
