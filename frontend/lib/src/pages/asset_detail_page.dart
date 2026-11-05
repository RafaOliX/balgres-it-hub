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
    final picked = source == ImageSource.gallery ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85) : [if (await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85) != null) (await picker.pickImage(source: ImageSource.camera))!].whereType<XFile>().toList();
    if (picked.isEmpty) return;
    try {
      await ref.read(inventarioApiProvider).subirImagenes(_asset!.assetTag, picked);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminarImagen(ItAssetImage img) async {
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text(widget.assetTag),
          actions: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
              if (_asset != null) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssetEditPage(asset: _asset!)));
                _load(); // Recargar si se editó
              }
            }),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _eliminarActivo),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Detalles'), Tab(text: 'Historial')]),
        ),
        body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : TabBarView(
          children: [
            // TAB 1: DETALLES
            ListView(padding: const EdgeInsets.all(16), children: [
              _galeriaFotos(),
              const SizedBox(height: 16),
              _card('Información', [
                _kv('Tag', _asset!.assetTag),
                _kv('Categoría', _asset!.category),
                _kv('Marca', _asset!.brand),
                _kv('Modelo', _asset!.model),
                _kv('S/N', _asset!.serialNumber),
                _kv('Ubicación', _asset!.location ?? '—'),
                _kv('Estado', _asset!.status ?? '—'),
              ]),
              if (_asset!.notes != null && _asset!.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _card('Notas', [Text(_asset!.notes!, style: const TextStyle(fontSize: 13, height: 1.5))]),
              ],
            ]),
            // TAB 2: HISTORIAL
            _history.isEmpty ? const Center(child: Text('Sin cambios registrados')) : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final h = _history[i];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: const Icon(Icons.history, color: Colors.blue)),
                  title: Text('Cambió: ${h.fieldName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('De: ${h.oldValue ?? "vacío"}\nA: ${h.newValue ?? "vacío"}', style: const TextStyle(fontSize: 12)),
                  trailing: Text(h.changedAt.toString().substring(0, 16), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _galeriaFotos() {
    final imgs = _asset!.images;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Row(children: [
            const Expanded(child: Text('FOTOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))),
            TextButton.icon(onPressed: _agregarImagenes, icon: const Icon(Icons.add_a_photo_outlined, size: 16), label: const Text('Agregar')),
          ]),
          if (imgs.isEmpty) const Text('Sin fotos', style: TextStyle(color: Colors.grey, fontSize: 12)) else
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: imgs.length,
            itemBuilder: (_, i) => Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imgs[i].url, fit: BoxFit.cover, width: double.infinity, height: double.infinity)),
              Positioned(top: 0, right: 0, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black45), onPressed: () => _eliminarImagen(imgs[i]))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)), const SizedBox(height: 10), ...children]),
  );

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 80, child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey))), Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))]));
}
