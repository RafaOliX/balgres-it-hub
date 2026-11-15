import 'dart:async';

import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';

const kPinKinds = <(String, String, IconData)>[
  ('camara', 'Cámara', Icons.videocam),
  ('nvr', 'NVR / DVR', Icons.storage),
  ('switch', 'Switch', Icons.device_hub),
  ('ap', 'Access Point', Icons.wifi),
  ('rack', 'Rack', Icons.dns),
  ('router', 'Router', Icons.router),
  ('otro', 'Otro', Icons.place),
];

IconData _iconOf(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$3 ?? Icons.place;
String _labelOf(String kind) => kPinKinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? kind;

void _snack(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

// ====================================================================== lista
class PlanosPage extends ConsumerWidget {
  const PlanosPage({super.key});

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null || !context.mounted) return;
    final name = TextEditingController(text: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo plano'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Piso 1 · Cámaras')),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Subir')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(planosApiProvider).crear(name.text.trim(), notes.text.trim(), f.bytes!, f.name);
      ref.invalidate(planosProvider);
    } catch (e) {
      _snack(context, 'Error: ${apiError(e)}');
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Plano p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlanoViewerPage(id: p.id)));
    ref.invalidate(planosProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final async = ref.watch(planosProvider);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final list = async.valueOrNull ?? const <Plano>[];
    final canEdit = AuthSession.can('planos.editar');

    return Padding(
      padding: EdgeInsets.all(mobile ? 12 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Planos', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 6),
              Text('Croquis con cámaras, switches y racks', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recargar', onPressed: () => ref.invalidate(planosProvider)),
          if (canEdit) ...[
            const SizedBox(width: 4),
            FilledButton.icon(onPressed: () => _nuevo(context, ref), icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: Text(mobile ? 'Nuevo' : 'Subir plano')),
          ],
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: async.isLoading && list.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : async.hasError && list.isEmpty
                  ? Center(child: Text('Error: ${apiError(async.error!)}'))
                  : list.isEmpty
                      ? EmptyState(
                          icon: Icons.map_outlined,
                          title: 'Aún no hay planos',
                          subtitle: 'Sube una imagen del plano y coloca los equipos encima.',
                          action: canEdit ? 'Subir plano' : null,
                          onAction: canEdit ? () => _nuevo(context, ref) : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: cardDeco(context, radius: 14),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _open(context, ref, p),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 96,
                                          height: 64,
                                          child: Image.network(p.imageUrl, fit: BoxFit.cover, cacheWidth: 288, errorBuilder: (_, __, ___) => Container(color: c.panel, child: Icon(Icons.map_outlined, color: c.muted))),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                          if ((p.notes ?? '').isNotEmpty) Text(p.notes!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
                                          Text('Actualizado ${p.updatedAt.toString().substring(0, 16)}', style: TextStyle(fontSize: 11, color: c.muted)),
                                        ]),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${p.pinCount} pin${p.pinCount == 1 ? '' : 'es'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accent)),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(Icons.chevron_right, color: c.edge),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

// ====================================================================== visor con pines
class PlanoViewerPage extends ConsumerStatefulWidget {
  final int id;
  const PlanoViewerPage({super.key, required this.id});
  @override
  ConsumerState<PlanoViewerPage> createState() => _PlanoViewerPageState();
}

class _PlanoViewerPageState extends ConsumerState<PlanoViewerPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  Plano? _p;
  bool _loading = true, _addMode = false;
  Pin? _moving;
  String? _error;
  Timer? _timer;

  bool get _canEdit => AuthSession.can('planos.editar');

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true)); // refresca el estado en línea
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
      if (mounted) setState(() { _p = p; _error = null; });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = apiError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _body(Pin p, {double? x, double? y}) => {
        'x': x ?? p.x, 'y': y ?? p.y, 'kind': p.kind, 'label': p.label ?? '', 'asset_tag': p.assetTag ?? '', 'notes': p.notes ?? '',
      };

  Future<void> _onTap(TapUpDetails d, Size size) async {
    if (!_canEdit || (!_addMode && _moving == null)) return;
    final x = (d.localPosition.dx / size.width * 100).clamp(0.0, 100.0);
    final y = (d.localPosition.dy / size.height * 100).clamp(0.0, 100.0);
    final api = ref.read(planosApiProvider);
    if (_moving != null) {
      final m = _moving!;
      setState(() => _moving = null);
      try {
        await api.actualizarPin(widget.id, m.id, _body(m, x: x, y: y));
        await _load(silent: true);
      } catch (e) {
        _snack(context, 'Error: ${apiError(e)}');
      }
    } else {
      setState(() => _addMode = false);
      await _pinDialog(x: x, y: y);
    }
  }

  Future<void> _pinDialog({Pin? pin, double? x, double? y}) async {
    final label = TextEditingController(text: pin?.label ?? '');
    final asset = TextEditingController(text: pin?.assetTag ?? '');
    final notes = TextEditingController(text: pin?.notes ?? '');
    var kind = pin?.kind ?? 'camara';
    final canEdit = _canEdit;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: Text(pin == null ? 'Nuevo pin' : (canEdit ? 'Editar pin' : _labelOf(pin.kind))),
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
              ]),
            ),
          ),
          actionsOverflowButtonSpacing: 4,
          actions: [
            if (pin?.assetTag != null) TextButton(onPressed: () => Navigator.pop(ctx, 'asset'), child: const Text('Ver activo')),
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
        case 'move':
          setState(() => _moving = pin);
        case 'delete':
          await api.eliminarPin(widget.id, pin!.id);
          await _load(silent: true);
        case 'save':
          final body = {'x': pin?.x ?? x, 'y': pin?.y ?? y, 'kind': kind, 'label': label.text.trim(), 'asset_tag': asset.text.trim(), 'notes': notes.text.trim()};
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

  Future<void> _editPlano() async {
    final p = _p!;
    final name = TextEditingController(text: p.name);
    final notes = TextEditingController(text: p.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar plano'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *')),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(planosApiProvider).actualizar(p.id, {'name': name.text.trim(), 'notes': notes.text.trim()});
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
        content: Text('¿Eliminar "${_p!.name}" con sus ${_p!.pins.length} pin(es)? No se puede deshacer.'),
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

  Color _pinColor(SwissColors c, Pin p) {
    if (p.assetTag == null) return c.accent;
    if (p.isUp == null) return c.muted;
    return p.isUp! ? c.ok : c.bad;
  }

  Widget _canvas(SwissColors c, Plano p) => InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: AspectRatio(
            aspectRatio: p.aspect,
            child: LayoutBuilder(builder: (ctx, cs) {
              final size = cs.biggest;
              return GestureDetector(
                onTapUp: (d) => _onTap(d, size),
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: Image.network(p.imageUrl, fit: BoxFit.fill, errorBuilder: (_, __, ___) => Center(child: Text('No se pudo cargar la imagen', style: TextStyle(color: c.bad))))),
                  for (final pin in p.pins)
                    Positioned(
                      left: pin.x / 100 * size.width - 16,
                      top: pin.y / 100 * size.height - 16,
                      child: Tooltip(
                        message: [_labelOf(pin.kind), pin.label, pin.assetTag, pin.ip].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
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
                            child: Icon(_iconOf(pin.kind), size: 16, color: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final p = _p;
    final banner = _moving != null
        ? 'Toca el plano para colocar "${_moving!.label ?? _labelOf(_moving!.kind)}"'
        : (_addMode ? 'Toca el plano donde va el nuevo pin' : null);

    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(p?.name ?? 'Plano'),
        actions: [
          if (p != null && _canEdit)
            IconButton(
              icon: Icon(_addMode ? Icons.close : Icons.add_location_alt_outlined),
              tooltip: _addMode ? 'Cancelar' : 'Agregar pin',
              onPressed: () => setState(() { _addMode = !_addMode; _moving = null; }),
            ),
          if (p != null) IconButton(icon: const Icon(Icons.list_alt_outlined), tooltip: 'Lista de pines', onPressed: () => _scaffold.currentState?.openEndDrawer()),
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
                                leading: CircleAvatar(radius: 14, backgroundColor: _pinColor(c, pin), child: Icon(_iconOf(pin.kind), size: 15, color: Colors.white)),
                                title: Text(pin.label ?? _labelOf(pin.kind), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text([pin.assetTag, pin.ip].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        TextButton(onPressed: () => setState(() { _addMode = false; _moving = null; }), child: const Text('Cancelar')),
                      ]),
                    ),
                  Expanded(child: Container(color: c.panel, child: _canvas(c, p))),
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
