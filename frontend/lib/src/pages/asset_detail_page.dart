import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/catalogs.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
import 'asset_edit_page.dart';

const _border = Color(0xFFE5E7EB);
const _muted = Color(0xFF6B7280);

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      _load();
      _snack('Activo finalizado correctamente.', color: Colors.green);
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _etiqueta() async {
    try {
      await ref.read(inventarioApiProvider).descargarEtiquetas([_asset!.assetTag]);
    } catch (e) {
      _snack('No se pudo generar la etiqueta (¿falta la dependencia segno en el backend?)');
    }
  }

  Future<void> _acta() async {
    try {
      await ref.read(inventarioApiProvider).descargarPdf(_asset!.assetTag);
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
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
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
              DropdownButtonFormField<int>(
                value: empId, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Empleado *', border: OutlineInputBorder()),
                items: emps.map((e) => DropdownMenuItem(value: e.id, child: Text(e.department == null ? e.name : '${e.name} · ${e.department}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setM(() => empId = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder())),
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
      _load();
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
        content: SizedBox(width: 400, child: TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas / estado al devolver', border: OutlineInputBorder()))),
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
      _load();
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
      _load();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  Future<void> _eliminarImagen(ItAssetImage img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'), content: const Text('¿Borrar esta foto del activo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminarImagen(_asset!.assetTag, img.id);
      ref.invalidate(inventarioListProvider);
      _load();
    } catch (e) {
      _snack('Error: ${apiError(e)}');
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(16),
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
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text(widget.assetTag),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined), tooltip: 'Editar',
              onPressed: _asset == null ? null : () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssetEditPage(asset: _asset!)));
                _load();
              },
            ),
            IconButton(icon: const Icon(Icons.qr_code_2), tooltip: 'Etiqueta QR', onPressed: _asset == null ? null : _etiqueta),
            IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Acta PDF', onPressed: _asset == null ? null : _acta),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Enviar a papelera', onPressed: _asset == null ? null : _eliminar),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Detalles'), Tab(text: 'Asignaciones'), Tab(text: 'Historial')]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_detalles(), _asignaciones(), _historial()]),
      ),
    );
  }

  Widget _detalles() {
    final a = _asset!;
    return ListView(padding: const EdgeInsets.all(24), children: [
      if (a.isDraft)
        Container(
          margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 12),
            const Expanded(child: Text('Este equipo está guardado como Borrador. Aún no se ha finalizado el registro.', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500))),
            FilledButton(onPressed: _finalizarBorrador, child: const Text('Finalizar Registro')),
          ]),
        ),
      _galeriaFotos(),
      const SizedBox(height: 24),
      _card('Información', [
        _kv('Tag', a.assetTag),
        _kv('Cantidad', '${a.quantity} ${a.unit}'),
        _kv('Categoría', a.category),
        _kv('Marca', a.brand),
        _kv('Modelo', a.model),
        _kv('S/N', a.serialNumber ?? 'N/A'),
        _kv('Ubicación', a.location ?? '—'),
        _kv('Estado', a.status ?? '—'),
        _kv('Asignado a', a.assignedTo ?? '—'),
        _kv('Registrado', a.createdAt.toString().substring(0, 16)),
      ]),
      _card('Compra y garantía', [
        _kv('Fecha compra', a.purchaseDate == null ? '—' : dateToApi(a.purchaseDate)!),
        _kv('Costo', a.cost == null ? '—' : '\$${a.cost!.toStringAsFixed(2)}'),
        _kv('Proveedor', a.supplier ?? '—'),
        _kv('Factura', a.invoiceNumber ?? '—'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const SizedBox(width: 100, child: Text('Garantía', style: TextStyle(fontSize: 13, color: Colors.grey))),
            if (a.warrantyUntil == null) const Text('—') else ...[Text(dateToApi(a.warrantyUntil)!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), const SizedBox(width: 10), _warrantyChip(a.warrantyUntil!)],
          ]),
        ),
      ]),
      if (a.specs.isNotEmpty) _card('Datos técnicos', a.specs.entries.map((e) => _kv(e.key, e.value)).toList()),
      if (a.notes != null && a.notes!.isNotEmpty) _card('Notas', [Text(a.notes!, style: const TextStyle(fontSize: 14, height: 1.5))]),
    ]);
  }

  Widget _warrantyChip(DateTime d) {
    final days = d.difference(DateTime.now()).inDays;
    final (txt, color) = days < 0 ? ('Vencida', Colors.red) : (days <= 60 ? ('Vence en $days días', Colors.orange) : ('Vigente', Colors.green));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(txt, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _asignaciones() {
    final a = _asset!;
    final vigente = _assignments.where((x) => x.returnedAt == null).firstOrNull;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _card('Custodio actual', [
        if (a.assignedTo == null)
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Sin asignar', style: TextStyle(color: Colors.grey)))
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(a.assignedTo!, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: vigente == null ? null : Text('Desde ${vigente.assignedAt.toString().substring(0, 16)} · entregó ${vigente.deliveredBy}'),
          ),
        Row(children: [
          FilledButton.icon(onPressed: _asignar, icon: const Icon(Icons.person_add_alt, size: 18), label: Text(a.assignedTo == null ? 'Asignar' : 'Reasignar')),
          const SizedBox(width: 8),
          if (a.assignedTo != null) OutlinedButton.icon(onPressed: _devolver, icon: const Icon(Icons.keyboard_return, size: 18), label: const Text('Devolver')),
        ]),
      ]),
      _card('Historial de custodia', [
        if (_assignments.isEmpty) const Text('Sin movimientos', style: TextStyle(color: Colors.grey)),
        ..._assignments.map((x) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(x.returnedAt == null ? Icons.radio_button_checked : Icons.history, color: x.returnedAt == null ? Colors.green : Colors.grey),
              title: Text(x.employeeName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                '${x.assignedAt.toString().substring(0, 10)} → ${x.returnedAt?.toString().substring(0, 10) ?? 'vigente'}',
                if (x.notes != null) 'Entrega: ${x.notes}',
                if (x.returnNotes != null) 'Devolución: ${x.returnNotes}',
              ].join('\n')),
              isThreeLine: x.notes != null || x.returnNotes != null,
            )),
      ]),
    ]);
  }

  Widget _historial() => _history.isEmpty
      ? const Center(child: Text('Sin cambios registrados'))
      : ListView.separated(
          padding: const EdgeInsets.all(24), itemCount: _history.length, separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) {
            final h = _history[i];
            final esRegistro = h.fieldName == 'registro';
            return ListTile(
              leading: const Icon(Icons.history, color: Colors.blue),
              title: Text(esRegistro ? (h.newValue ?? 'Registro') : 'Cambió: ${h.fieldName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: esRegistro ? Text('Por ${h.changedBy}') : Text('De: ${h.oldValue ?? "vacío"} a: ${h.newValue ?? "vacío"}\nPor ${h.changedBy}'),
              trailing: Text(h.changedAt.toString().substring(0, 16), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            );
          },
        );

  Widget _galeriaFotos() {
    final imgs = _asset!.images;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('FOTOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _muted, letterSpacing: 0.8))),
            TextButton.icon(onPressed: _agregarImagenes, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Agregar')),
          ]),
          if (imgs.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Sin fotos', style: TextStyle(color: Colors.grey, fontSize: 13))))
          else
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal, itemCount: imgs.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => Stack(children: [
                  GestureDetector(
                    onTap: () => _showImageDialog(imgs[i].url),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imgs[i].url, width: 180, height: 140, fit: BoxFit.cover)),
                  ),
                  Positioned(
                    top: 6, right: 6,
                    child: Material(
                      color: Colors.redAccent, shape: const CircleBorder(),
                      child: InkWell(customBorder: const CircleBorder(), onTap: () => _eliminarImagen(imgs[i]), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete, size: 16, color: Colors.white))),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
        elevation: 0, margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _border)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _muted, letterSpacing: 0.8)),
            const SizedBox(height: 16),
            ...children,
          ]),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ]),
      );
}
