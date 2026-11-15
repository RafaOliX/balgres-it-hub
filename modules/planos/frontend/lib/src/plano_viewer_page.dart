import 'dart:async';
import 'dart:math' as math;

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'pins.dart';
import 'providers.dart';

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

enum _Tool { nav, pin, libre, flecha, borrar }

const _palette = <Color>[Color(0xFFE11D48), Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFF59E0B), Color(0xFF111827)];

Color _trazoColor(String hex) => Color(int.tryParse('FF${hex.replaceAll('#', '')}', radix: 16) ?? 0xFFE11D48);
String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _TrazosPainter extends CustomPainter {
  final List<Trazo> trazos;
  final Trazo? live;
  _TrazosPainter(this.trazos, this.live);

  @override
  void paint(Canvas canvas, Size size) {
    Offset o(List<double> q) => Offset(q[0] / 100 * size.width, q[1] / 100 * size.height);
    for (final t in [...trazos, if (live != null) live!]) {
      if (t.points.length < 2) continue;
      final paint = Paint()
        ..color = _trazoColor(t.color)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = t.width * size.width / 1000;
      if (t.kind == 'flecha') {
        final a = o(t.points.first), b = o(t.points.last);
        canvas.drawLine(a, b, paint);
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final len = math.max(paint.strokeWidth * 4, 10.0);
        for (final s in [-1, 1]) {
          canvas.drawLine(b, b - Offset(math.cos(ang + s * 0.5) * len, math.sin(ang + s * 0.5) * len), paint);
        }
      } else {
        final first = o(t.points.first);
        final path = Path()..moveTo(first.dx, first.dy);
        for (final q in t.points.skip(1)) {
          final p = o(q);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrazosPainter old) => true;
}

class PlanoViewerPage extends ConsumerStatefulWidget {
  final int id;
  const PlanoViewerPage({super.key, required this.id});
  @override
  ConsumerState<PlanoViewerPage> createState() => _PlanoViewerPageState();
}

class _PlanoViewerPageState extends ConsumerState<PlanoViewerPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  Plano? _p;
  List<Trazo> _trazos = [];
  bool _loading = true, _busy = false, _showTrazos = true, _showPines = true;
  _Tool _tool = _Tool.nav;
  Pin? _moving;
  String? _error;
  Timer? _timer;
  Color _color = _palette.first;
  double _width = 4;
  List<List<double>> _cur = [];

  bool get _canEdit => AuthSession.can('planos.editar');
  bool get _drawing => _tool == _Tool.libre || _tool == _Tool.flecha;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && _cur.isEmpty) _load(silent: true); // refresca el estado en línea
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final p = await ref.read(planosApiProvider).obtener(widget.id);
      if (mounted) setState(() { _p = p; _trazos = p.trazos; _error = null; });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = apiError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- pines
  Map<String, dynamic> _body(Pin p, {double? x, double? y}) => {
        'x': x ?? p.x, 'y': y ?? p.y, 'kind': p.kind, 'label': p.label ?? '', 'asset_tag': p.assetTag ?? '',
        'notes': p.notes ?? '', 'nota_id': p.notaId,
      };

  List<double> _pt(Offset o, Size s) => [
        (((o.dx / s.width * 100).clamp(0.0, 100.0) as num) * 100).roundToDouble() / 100,
        (((o.dy / s.height * 100).clamp(0.0, 100.0) as num) * 100).roundToDouble() / 100,
      ];

  Future<void> _onTap(TapUpDetails d, Size size) async {
    if (_moving != null && _canEdit) {
      final m = _moving!;
      final q = _pt(d.localPosition, size);
      setState(() => _moving = null);
      try {
        await ref.read(planosApiProvider).actualizarPin(widget.id, m.id, _body(m, x: q[0], y: q[1]));
        await _load(silent: true);
      } catch (e) {
        _snack(context, 'Error: ${apiError(e)}');
      }
    } else if (_tool == _Tool.pin && _canEdit) {
      final q = _pt(d.localPosition, size);
      setState(() => _tool = _Tool.nav);
      await _pinDialog(x: q[0], y: q[1]);
    } else if (_tool == _Tool.borrar) {
      final t = _hit(d.localPosition, size);
      if (t != null) await _deleteTrazo(t);
    }
  }

  Future<void> _pinDialog({Pin? pin, double? x, double? y}) async {
    final label = TextEditingController(text: pin?.label ?? '');
    final asset = TextEditingController(text: pin?.assetTag ?? '');
    final notes = TextEditingController(text: pin?.notes ?? '');
    var kind = pin?.kind ?? 'camara';
    int? notaId = pin?.notaId;
    final canEdit = _canEdit;
    final notas = canEdit ? await ref.read(planosApiProvider).getNotas() : const <NotaRef>[];
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: Text(pin == null ? 'Nuevo pin' : (canEdit ? 'Editar pin' : pinLabel(pin.kind))),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (pin?.ip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('IP ${pin!.ip} · ${pin.isUp == null ? 'sin verificar' : (pin.isUp! ? 'en línea' : 'sin respuesta')}', style: TextStyle(fontWeight: FontWeight.w700, color: ctx.sw.muted)),
                  ),
                DropdownButtonFormField<String>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [for (final k in kPinKinds) DropdownMenuItem(value: k.$1, child: Text(k.$2))],
                  onChanged: canEdit ? (v) => setM(() => kind = v!) : null,
                ),
                const SizedBox(height: 12),
                TextField(controller: label, readOnly: !canEdit, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Cámara entrada principal')),
                const SizedBox(height: 12),
                TextField(controller: asset, readOnly: !canEdit, decoration: const InputDecoration(labelText: 'Tag de activo (opcional)', helperText: 'Ej: CAM-001. Muestra su estado en línea desde Redes')),
                const SizedBox(height: 12),
                TextField(controller: notes, readOnly: !canEdit, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                if (canEdit) ...[
                  const SizedBox(height: 12),
                  SearchSelect<NotaRef>(
                    label: 'Nota de documentación',
                    value: notas.where((n) => n.id == notaId).firstOrNull,
                    options: notas,
                    display: (n) => n.title,
                    hint: 'Escribe para buscar una nota…',
                    onChanged: (n) => setM(() => notaId = n?.id),
                  ),
                ],
              ]),
            ),
          ),
          actionsOverflowButtonSpacing: 4,
          actions: [
            if (pin?.assetTag != null) TextButton(onPressed: () => Navigator.pop(ctx, 'asset'), child: const Text('Ver activo')),
            if (pin?.notaId != null) TextButton(onPressed: () => Navigator.pop(ctx, 'nota'), child: const Text('Ver nota')),
            if (pin != null && canEdit) TextButton(onPressed: () => Navigator.pop(ctx, 'move'), child: const Text('Mover')),
            if (pin != null && AuthSession.can('planos.eliminar')) TextButton(style: TextButton.styleFrom(foregroundColor: ctx.sw.bad), onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Eliminar')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            if (canEdit) FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final api = ref.read(planosApiProvider);
    try {
      switch (action) {
        case 'asset':
          context.push('/inventario/detalle/${pin!.assetTag}');
        case 'nota':
          context.push('/notas/${pin!.notaId}');
        case 'move':
          setState(() { _moving = pin; _tool = _Tool.nav; });
        case 'delete':
          await api.eliminarPin(widget.id, pin!.id);
          await _load(silent: true);
        case 'save':
          final body = {
            'x': pin?.x ?? x, 'y': pin?.y ?? y, 'kind': kind, 'label': label.text.trim(),
            'asset_tag': asset.text.trim(), 'notes': notes.text.trim(), 'nota_id': notaId,
          };
          if (pin == null) {
            await api.crearPin(widget.id, body);
          } else {
            await api.actualizarPin(widget.id, pin.id, body);
          }
          await _load(silent: true);
      }
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- dibujo
  void _penDown(Offset o, Size s) {
    if (!_canEdit) return;
    setState(() => _cur = [_pt(o, s)]);
  }

  void _penMove(Offset o, Size s) {
    if (_cur.isEmpty) return;
    final q = _pt(o, s);
    if (_tool == _Tool.flecha) {
      setState(() => _cur = [_cur.first, q]);
      return;
    }
    final l = _cur.last;
    if ((q[0] - l[0]).abs() + (q[1] - l[1]).abs() < 0.25 || _cur.length >= 1500) return;
    setState(() => _cur.add(q));
  }

  Future<void> _penUp() async {
    final pts = List<List<double>>.from(_cur);
    setState(() => _cur = []);
    if (!_canEdit || pts.length < 2) return;
    final arrow = _tool == _Tool.flecha;
    if (arrow) {
      final d = math.sqrt(math.pow(pts.last[0] - pts.first[0], 2) + math.pow(pts.last[1] - pts.first[1], 2));
      if (d < 1.5) return; // toque accidental
    }
    final tmp = Trazo(id: -DateTime.now().microsecondsSinceEpoch, kind: arrow ? 'flecha' : 'libre', color: _hex(_color), width: _width, points: pts);
    setState(() => _trazos = [..._trazos, tmp]);
    _busy = true;
    try {
      await ref.read(planosApiProvider).crearTrazo(widget.id, {'kind': tmp.kind, 'color': tmp.color, 'width': tmp.width, 'points': pts});
      await _load(silent: true);
    } catch (e) {
      if (mounted) setState(() => _trazos = _trazos.where((x) => x.id != tmp.id).toList());
      _snack(context, 'Error: ${apiError(e)}');
    } finally {
      _busy = false;
    }
  }

  double _distSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / l2).clamp(0.0, 1.0).toDouble();
    return (p - (a + ab * t)).distance;
  }

  Trazo? _hit(Offset o, Size s) {
    if (!_showTrazos) return null;
    Trazo? best;
    var bestD = 14.0;
    for (final t in _trazos) {
      final pts = [for (final q in t.points) Offset(q[0] / 100 * s.width, q[1] / 100 * s.height)];
      for (var i = 0; i < pts.length - 1; i++) {
        final d = _distSeg(o, pts[i], pts[i + 1]);
        if (d < bestD) {
          bestD = d;
          best = t;
        }
      }
    }
    return best;
  }

  Future<void> _deleteTrazo(Trazo t) async {
    if (t.id < 0) return; // aún guardándose
    setState(() => _trazos = _trazos.where((x) => x.id != t.id).toList());
    try {
      await ref.read(planosApiProvider).eliminarTrazo(widget.id, t.id);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
      await _load(silent: true);
    }
  }

  Future<void> _clearTrazos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar todo el dibujo'),
        content: Text('Se borrarán los ${_trazos.length} trazo(s) de este plano. Los pines no se tocan. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: ctx.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(planosApiProvider).limpiarTrazos(widget.id);
      await _load(silent: true);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- plano
  Future<void> _editPlano() async {
    final p = _p!;
    final name = TextEditingController(text: p.name);
    final notes = TextEditingController(text: p.notes ?? '');
    int? notaId = p.notaId;
    final notas = await ref.read(planosApiProvider).getNotas();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: const Text('Editar plano'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
              const SizedBox(height: 12),
              TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
              const SizedBox(height: 12),
              SearchSelect<NotaRef>(
                label: 'Nota de documentación',
                value: notas.where((n) => n.id == notaId).firstOrNull,
                options: notas,
                display: (n) => n.title,
                hint: 'Escribe para buscar una nota…',
                onChanged: (n) => setM(() => notaId = n?.id),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(planosApiProvider).actualizar(p.id, {'name': name.text.trim(), 'notes': notes.text.trim(), 'nota_id': notaId});
      await _load(silent: true);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _deletePlano() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar plano'),
        content: Text('¿Eliminar "${_p!.name}" con sus ${_p!.pins.length} pin(es) y su dibujo? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: ctx.sw.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(planosApiProvider).eliminar(widget.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- UI
  Color _pinColor(SwissColors c, Pin p) {
    if (p.assetTag == null) return c.accent;
    if (p.isUp == null) return c.muted;
    return p.isUp! ? c.ok : c.bad;
  }

  Widget _canvas(SwissColors c, Plano p) {
    final drawing = _drawing;
    final blockPins = drawing || _tool == _Tool.borrar;
    final live = _cur.length >= 2
        ? Trazo(id: 0, kind: _tool == _Tool.flecha ? 'flecha' : 'libre', color: _hex(_color), width: _width, points: _cur)
        : null;
    return InteractiveViewer(
      maxScale: 8,
      panEnabled: !drawing,
      scaleEnabled: !drawing,
      child: Center(
        child: AspectRatio(
          aspectRatio: p.aspect,
          child: LayoutBuilder(builder: (ctx, cs) {
            final size = cs.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTap(d, size),
              onPanStart: drawing ? (d) => _penDown(d.localPosition, size) : null,
              onPanUpdate: drawing ? (d) => _penMove(d.localPosition, size) : null,
              onPanEnd: drawing ? (_) => _penUp() : null,
              onPanCancel: drawing ? () => setState(() => _cur = []) : null,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: Image.network(p.imageUrl, fit: BoxFit.fill, errorBuilder: (_, __, ___) => Center(child: Text('No se pudo cargar la imagen', style: TextStyle(color: c.bad))))),
                if (_showTrazos) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _TrazosPainter(_trazos, live)))),
                if (_showPines)
                  for (final pin in p.pins)
                    Positioned(
                      left: pin.x / 100 * size.width - 16,
                      top: pin.y / 100 * size.height - 16,
                      child: IgnorePointer(
                        ignoring: blockPins,
                        child: Tooltip(
                          message: [pinLabel(pin.kind), pin.label, pin.assetTag, pin.ip].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                          child: GestureDetector(
                            onTap: () => _pinDialog(pin: pin),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _pinColor(c, pin),
                                shape: BoxShape.circle,
                                border: Border.all(color: _moving?.id == pin.id ? c.warn : Colors.white, width: _moving?.id == pin.id ? 3 : 2),
                                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                              ),
                              child: Icon(pinIcon(pin.kind), size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _toolbar(SwissColors c) {
    Widget tool(_Tool t, IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: _tool == t,
            onSelected: (_) => setState(() {
              _tool = _tool == t ? _Tool.nav : t;
              _moving = null;
              if (_tool == _Tool.libre || _tool == _Tool.flecha || _tool == _Tool.borrar) _showTrazos = true;
            }),
          ),
        );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (_canEdit) ...[
            tool(_Tool.pin, Icons.add_location_alt_outlined, 'Pin'),
            tool(_Tool.libre, Icons.edit_outlined, 'Lápiz'),
            tool(_Tool.flecha, Icons.arrow_right_alt, 'Flecha'),
          ],
          if (AuthSession.can('planos.eliminar')) tool(_Tool.borrar, Icons.backspace_outlined, 'Borrar trazo'),
          if (_drawing) ...[
            const SizedBox(width: 8),
            for (final col in _palette)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = col),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: _color == col ? c.ink : c.line, width: _color == col ? 3 : 1)),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 2.0, label: Text('Fino')),
                ButtonSegment(value: 4.0, label: Text('Medio')),
                ButtonSegment(value: 8.0, label: Text('Grueso')),
              ],
              selected: {_width},
              onSelectionChanged: (s) => setState(() => _width = s.first),
            ),
          ],
          const SizedBox(width: 16),
          FilterChip(label: const Text('Dibujo'), selected: _showTrazos, onSelected: (v) => setState(() => _showTrazos = v)),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Pines'), selected: _showPines, onSelected: (v) => setState(() => _showPines = v)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final p = _p;
    final banner = _moving != null
        ? 'Toca el plano para colocar "${_moving!.label ?? pinLabel(_moving!.kind)}"'
        : switch (_tool) {
            _Tool.pin => 'Toca el plano donde va el nuevo pin',
            _Tool.libre => 'Dibuja arrastrando. El zoom se desactiva mientras dibujas: pulsa de nuevo la herramienta para volver a navegar',
            _Tool.flecha => 'Arrastra para trazar la flecha',
            _Tool.borrar => 'Toca un trazo para eliminarlo',
            _Tool.nav => null,
          };
    final docTip = p?.notaId == null ? '' : 'Documentación: ${p!.notaTitle ?? 'nota #${p.notaId}'}';

    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(p?.name ?? 'Plano'),
        actions: [
          if (p?.notaId != null)
            IconButton(icon: const Icon(Icons.description_outlined), tooltip: docTip, onPressed: () => context.push('/notas/${p!.notaId}')),
          if (p != null) IconButton(icon: const Icon(Icons.list_alt_outlined), tooltip: 'Lista de pines', onPressed: () => _scaffold.currentState?.openEndDrawer()),
          if (p != null && AuthSession.can('planos.eliminar') && _trazos.isNotEmpty)
            IconButton(icon: const Icon(Icons.layers_clear_outlined), tooltip: 'Borrar todo el dibujo', onPressed: _clearTrazos),
          if (p != null && _canEdit) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar plano', onPressed: _editPlano),
          if (p != null && AuthSession.can('planos.eliminar')) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar plano', onPressed: _deletePlano),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: p == null
          ? null
          : Drawer(
              child: SafeArea(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.all(16), child: SectionLabel('Pines (${p.pins.length})')),
                  Expanded(
                    child: p.pins.isEmpty
                        ? Padding(padding: const EdgeInsets.all(16), child: Text('Aún no hay pines.', style: TextStyle(color: c.muted)))
                        : ListView(children: [
                            for (final pin in p.pins)
                              ListTile(
                                dense: true,
                                leading: CircleAvatar(radius: 14, backgroundColor: _pinColor(c, pin), child: Icon(pinIcon(pin.kind), size: 15, color: Colors.white)),
                                title: Text(pin.label ?? pinLabel(pin.kind), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text([pin.assetTag, pin.ip].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: pin.notaId == null ? null : Icon(Icons.description_outlined, size: 16, color: c.muted),
                                onTap: () {
                                  Navigator.pop(context);
                                  _pinDialog(pin: pin);
                                },
                              ),
                          ]),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || p == null
              ? Center(child: Text(_error ?? 'Plano no encontrado'))
              : Column(children: [
                  if (banner != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: c.accent.withValues(alpha: 0.12),
                      child: Row(children: [
                        Icon(Icons.touch_app_outlined, size: 18, color: c.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(banner, style: TextStyle(fontWeight: FontWeight.w600, color: c.accent))),
                        TextButton(onPressed: () => setState(() { _tool = _Tool.nav; _moving = null; }), child: const Text('Listo')),
                      ]),
                    ),
                  Expanded(child: Container(color: c.panel, child: _canvas(c, p))),
                  _toolbar(c),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(spacing: 14, children: [
                      for (final l in [('En línea', c.ok), ('Sin respuesta', c.bad), ('Sin verificar', c.muted), ('Sin activo', c.accent)])
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: l.$2, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(l.$1, style: TextStyle(fontSize: 11, color: c.muted)),
                        ]),
                    ]),
                  ),
                ]),
    );
  }
}
