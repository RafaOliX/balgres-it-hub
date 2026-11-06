import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';
import '../models/it_asset_history.dart';
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
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(inventarioApiProvider);
      final list = await api.buscar(widget.assetTag);
      final exact = list.where((a) => a.assetTag == widget.assetTag).firstOrNull;
      if (exact != null) {
        final h = await api.getHistorial(exact.assetTag);
        setState(() { _asset = exact; _history = h; });
      } else {
        setState(() => _error = 'Activo no encontrado');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ARREGLO CÁMARA: Igual que en el formulario, ya no la abre dos veces
  Future<void> _agregarImagenes() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])),
    );
    if (source == null) return;
    
    final picker = ImagePicker();
    List<XFile> picked = [];
    if (source == ImageSource.camera) {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
      if (photo != null) picked.add(photo);
    } else {
      final List<XFile> photos = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);
      picked.addAll(photos);
    }

    if (picked.isEmpty) return;
    try {
      await ref.read(inventarioApiProvider).subirImagenes(_asset!.assetTag, picked);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarImagen(ItAssetImage img) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eliminar foto'), content: const Text('¿Borrar esta foto del activo?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
      ],
    ));
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminarImagen(_asset!.assetTag, img.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarActivo() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Eliminar activo'), content: Text('¿Borrar ${_asset!.assetTag}?'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
    ]));
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminar(_asset!.assetTag);
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // MEJORADO: Ahora acepta URL relativa y funciona en web/móvil
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)),
            Positioned(
              top: 0, right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text(widget.assetTag),
          actions: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
              if (_asset != null) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssetEditPage(asset: _asset!)));
                _load();
              }
            }),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _asset != null ? _eliminarActivo : null),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Detalles'), Tab(text: 'Historial')]),
        ),
        body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : TabBarView(
          children: [
            ListView(padding: const EdgeInsets.all(24), children: [
              _galeriaFotos(),
              const SizedBox(height: 24),
              _card('Información', [
                _kv('Tag', _asset!.assetTag),
                _kv('Cantidad', '${_asset!.quantity} ${_asset!.unit}'),
                _kv('Categoría', _asset!.category),
                _kv('Marca', _asset!.brand),
                _kv('Modelo', _asset!.model),
                _kv('S/N', _asset!.serialNumber ?? 'N/A'),
                _kv('Ubicación', _asset!.location ?? '—'),
                _kv('Estado', _asset!.status ?? '—'),
                _kv('Asignado a', _asset!.assignedTo ?? '—'),
              ]),
              if (_asset!.notes != null && _asset!.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _card('Notas', [Text(_asset!.notes!, style: const TextStyle(fontSize: 14, height: 1.5))]),
              ],
            ]),
            _history.isEmpty ? const Center(child: Text('Sin cambios registrados')) : ListView.separated(
              padding: const EdgeInsets.all(24), itemCount: _history.length, separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: Text('Cambió: ${_history[i].fieldName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('De: ${_history[i].oldValue ?? "vacío"} a: ${_history[i].newValue ?? "vacío"}'),
                trailing: Text(_history[i].changedAt.toString().substring(0, 16), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _galeriaFotos() {
    final imgs = _asset!.images;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('FOTOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF6B7280), letterSpacing: 0.8))),
                TextButton.icon(onPressed: _agregarImagenes, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Agregar')),
              ],
            ),
            if (imgs.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Sin fotos', style: TextStyle(color: Colors.grey, fontSize: 13))))
            else
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imgs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _showImageDialog(context, imgs[i].url),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imgs[i].url, width: 180, height: 140, fit: BoxFit.cover)),
                      ),
                      Positioned(
                        top: 6, right: 6,
                        child: Material(
                          color: Colors.redAccent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _eliminarImagen(imgs[i]),
                            child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete, size: 16, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF6B7280), letterSpacing: 0.8)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey))), Expanded(child: Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)))]));
}
