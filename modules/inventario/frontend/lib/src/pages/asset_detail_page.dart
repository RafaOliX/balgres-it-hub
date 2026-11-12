import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
import '../ui/swiss.dart';
import '../widgets/asset_card.dart';
import '../widgets/search_select.dart';
import 'acta_templates_page.dart';
import 'asset_edit_page.dart';

class AssetDetailPage extends ConsumerStatefulWidget {
  final String assetTag;
  const AssetDetailPage({super.key, required this.assetTag});
  @override
  ConsumerState<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends ConsumerState<AssetDetailPage> {
  ItAsset? _asset;
  List<ItAssetHistory> _history = [];
  List<Assignment> _assignments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m, {Color? color}) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(inventarioApiProvider);
      final asset = await api.obtener(widget.assetTag);
      final h = await api.getHistorial(asset.assetTag);
      final a = await api.getAsignaciones(asset.assetTag);
      if (mounted) {
        setState(() {
          _asset = asset;
          _history = h;
          _assignments = a;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finalizarBorrador() async {
    try {
      await ref.read(inventarioApiProvider).actualizar(_asset!.assetTag, {'is_draft': false});
      ref.invalidate(inventarioListProvider);
      _load(silent: true);
      _snack('Activo finalizado correctamente.', color: Colors.green);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _ajustar(int n) async {
    try {
      await ref.read(inventarioApiProvider).ajustarStock(_asset!.assetTag, n);
      ref.invalidate(inventarioListProvider);
      await _load(silent: true);
      _snack(n > 0 ? 'Se agregó 1 unidad' : 'Se restó 1 unidad');
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _etiqueta() async {
    try {
      await ref.read(inventarioApiProvider).descargarEtiquetas([_asset!.assetTag]);
    } catch (e) {
      _snack('No se pudo generar la etiqueta: ${apiError(e)}');
    }
  }

  Future<void> _acta() async {
    final t = await showActaPicker(context, title: 'Acta del equipo: elige la plantilla');
    if (t == null || !mounted) return;
    try {
      await ref.read(inventarioApiProvider).descargarPdf(_asset!.assetTag, templateId: t.id);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar a la papelera'),
        content: Text('¿Enviar ${_asset!.assetTag} a la papelera? Podrás restaurarlo después.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminar(_asset!.assetTag);
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- asignaciones
  Future<void> _asignar() async {
    final emps = (await ref.read(empleadosProvider.future)).where((e) => e.active).toList();
    if (emps.isEmpty) {
      _snack('Primero registra empleados (menú ⋮ → Empleados y ubicaciones).');
      return;
    }
    int? empId;
    final notes = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: const Text('Asignar activo'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SearchSelect<Employee>(
                label: 'Empleado',
                required: true,
                allowClear: false,
                value: emps.where((e) => e.id == empId).firstOrNull,
                options: emps,
                display: (e) => e.name,
                searchText: (e) => '${e.department ?? ''} ${e.position ?? ''} ${e.email ?? ''} ${e.extension ?? ''}',
                subtitle: (e) => [e.position, e.department].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                onChanged: (e) => setM(() => empId = e?.id),
              ),
              const SizedBox(height: 12),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: empId == null ? null : () => Navigator.pop(ctx, true), child: const Text('Asignar')),
          ],
        ),
      ),
    );
    if (ok != true || empId == null) return;
    try {
      await ref.read(inventarioApiProvider).asignar(_asset!.assetTag, empId!, notes.text.trim());
      ref.invalidate(inventarioListProvider);
      _load(silent: true);
      _snack('Activo asignado.', color: Colors.green);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _devolver() async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar devolución'),
        content: SizedBox(width: 400, child: TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas / estado al devolver'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Devolver')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).devolver(_asset!.assetTag, notes.text.trim());
      ref.invalidate(inventarioListProvider);
      _load(silent: true);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  // ---------------------------------------------------------------- fotos
  Future<void> _agregarImagenes() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final picked = <XFile>[];
    if (source == ImageSource.camera) {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
      if (photo != null) picked.add(photo);
    } else {
      picked.addAll(await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85));
    }
    if (picked.isEmpty) return;
    try {
      await ref.read(inventarioApiProvider).subirImagenes(_asset!.assetTag, picked);
      ref.invalidate(inventarioListProvider);
      _load(silent: true);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _eliminarImagen(ItAssetImage img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Borrar esta foto del activo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminarImagen(_asset!.assetTag, img.id);
      ref.invalidate(inventarioListProvider);
      _load(silent: true);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(alignment: Alignment.center, children: [
          InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)),
          Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black54), onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.assetTag),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: _asset == null
                  ? null
                  : () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => AssetEditPage(asset: _asset!)));
                      ref.invalidate(inventarioListProvider);
                      _load(silent: true);
                    },
            ),
            IconButton(icon: const Icon(Icons.copy_all_outlined), tooltip: 'Duplicar equipo', onPressed: _asset == null ? null : () => openNewAsset(context, template: _asset)),
            IconButton(icon: const Icon(Icons.qr_code_2), tooltip: 'Etiqueta QR', onPressed: _asset == null ? null : _etiqueta),
            IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Acta PDF', onPressed: _asset == null ? null : _acta),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Enviar a papelera', onPressed: _asset == null ? null : _eliminar),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Detalles'), Tab(text: 'Asignaciones'), Tab(text: 'Historial')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_detalles(), _asignaciones(), _historial()]),
      ),
    );
  }

  Widget _wrap(Widget child, {double max = 1000}) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(padding: EdgeInsets.all(wide ? 32 : 20), children: [
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child)),
    ]);
  }

  Widget _detalles() {
    final a = _asset!;
    final c = context.sw;
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? const <Category>[];
    final cat = cats.where((x) => x.id == a.categoryId).firstOrNull;
    final consumible = cat != null && !cat.requiresSn; // cables, toners… (sin S/N)
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.assetTag, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2))),
          StatusTag(status: a.status, draft: a.isDraft),
        ]),
        const SizedBox(height: 4),
        Text('${a.category} · ${a.brand} ${a.model}', style: TextStyle(fontSize: 15, color: c.muted)),
      ]),
    );

    final draftBanner = a.isDraft
        ? Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.panel, border: Border(left: BorderSide(color: c.accent, width: 3))),
            child: Row(children: [
              const Expanded(child: Text('Este equipo está guardado como borrador. Aún no se ha finalizado el registro.', style: TextStyle(fontWeight: FontWeight.w500))),
              const SizedBox(width: 12),
              FilledButton(onPressed: _finalizarBorrador, child: const Text('Finalizar registro')),
            ]),
          )
        : const SizedBox.shrink();

    final info = SwissSection('Información', [
      Kv('Categoría', a.category),
      Kv('Marca', a.brand),
      Kv('Modelo', a.model),
      Kv('S/N', a.serialNumber ?? 'N/A'),
      Kv.widget(
        'Cantidad',
        Row(children: [
          Text('${a.quantity} ${a.unit}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          if (consumible) ...[const SizedBox(width: 12), _stockBtn(Icons.remove, -1), const SizedBox(width: 6), _stockBtn(Icons.add, 1)],
        ]),
      ),
      Kv('Ubicación', a.location ?? '—'),
      Kv('Estado', a.status ?? '—'),
      Kv.widget(
        'Asignado a',
        a.employeeId == null
            ? Text(a.assignedTo ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
            : InkWell(
                onTap: () => context.push('/empleados/${a.employeeId}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(a.assignedTo ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 14, color: c.accent),
                ]),
              ),
      ),
      Kv('Registrado', a.createdAt.toString().substring(0, 16)),
    ]);

    final right = <Widget>[
      if (a.specs.isNotEmpty) SwissSection('Datos técnicos', a.specs.entries.map((e) => Kv(e.key, e.value)).toList()),
      if ((a.notes ?? '').isNotEmpty) SwissSection('Notas', [Text(a.notes!, style: const TextStyle(fontSize: 14, height: 1.5))]),
    ];

    return _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      draftBanner,
      _galeria(),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: info),
          const SizedBox(width: 48),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
        ])
      else ...[info, ...right],
    ]));
  }

  Widget _stockBtn(IconData icon, int n) => IconButton.outlined(
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        icon: Icon(icon),
        tooltip: n > 0 ? 'Sumar 1 (ingreso)' : 'Restar 1 (uso)',
        onPressed: () => _ajustar(n),
      );

  Widget _galeria() {
    final imgs = _asset!.images;
    final c = context.sw;
    return SwissSection(
      'Fotos',
      [
        if (imgs.isEmpty)
          Text('Sin fotos', style: TextStyle(color: c.muted))
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imgs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => Stack(children: [
                GestureDetector(
                  onTap: () => _showImageDialog(imgs[i].url),
                  child: ClipRRect(borderRadius: BorderRadius.circular(2), child: Image.network(imgs[i].url, width: 200, height: 150, fit: BoxFit.cover)),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: c.ink,
                    child: InkWell(onTap: () => _eliminarImagen(imgs[i]), child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.close, size: 16, color: c.bg))),
                  ),
                ),
              ]),
            ),
          ),
      ],
      trailing: TextButton.icon(onPressed: _agregarImagenes, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Agregar')),
    );
  }

  Widget _asignaciones() {
    final a = _asset!;
    final c = context.sw;
    final vigente = _assignments.where((x) => x.returnedAt == null).firstOrNull;
    return _wrap(
      max: 800,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwissSection('Custodio actual', [
          if (a.assignedTo == null)
            Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Sin asignar', style: TextStyle(color: c.muted)))
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.assignedTo!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                if (vigente != null)
                  Text('Desde ${vigente.assignedAt.toString().substring(0, 16)} · entregó ${vigente.deliveredBy}', style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
          Row(children: [
            FilledButton.icon(onPressed: _asignar, icon: const Icon(Icons.person_add_alt, size: 18), label: Text(a.assignedTo == null ? 'Asignar' : 'Reasignar')),
            const SizedBox(width: 8),
            if (a.assignedTo != null) OutlinedButton.icon(onPressed: _devolver, icon: const Icon(Icons.keyboard_return, size: 18), label: const Text('Devolver')),
          ]),
        ]),
        SwissSection('Historial de custodia', [
          if (_assignments.isEmpty) Text('Sin movimientos', style: TextStyle(color: c.muted)),
          for (final x in _assignments)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 170,
                  child: Text('${x.assignedAt.toString().substring(0, 10)} → ${x.returnedAt?.toString().substring(0, 10) ?? 'vigente'}',
                      style: TextStyle(fontSize: 12, color: x.returnedAt == null ? c.ok : c.muted, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.employeeName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (x.notes != null) Text('Entrega: ${x.notes}', style: TextStyle(fontSize: 13, color: c.muted)),
                    if (x.returnNotes != null) Text('Devolución: ${x.returnNotes}', style: TextStyle(fontSize: 13, color: c.muted)),
                  ]),
                ),
              ]),
            ),
        ]),
      ]),
    );
  }

  Widget _historial() {
    final c = context.sw;
    if (_history.isEmpty) return const Center(child: Text('Sin cambios registrados'));
    return _wrap(
      max: 900,
      Column(children: [
        for (final h in _history)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(h.changedAt.toString().substring(0, 16), style: TextStyle(fontSize: 12, color: c.muted))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.fieldName == 'registro' ? (h.newValue ?? 'Registro') : 'Cambió ${h.fieldName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    h.fieldName == 'registro' ? 'Por ${h.changedBy}' : 'De: ${h.oldValue ?? "vacío"} a: ${h.newValue ?? "vacío"} · ${h.changedBy}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
