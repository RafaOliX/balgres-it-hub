import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';

class AssetDetailPage extends ConsumerStatefulWidget {
  final String assetTag;
  const AssetDetailPage({super.key, required this.assetTag});

  @override
  ConsumerState<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends ConsumerState<AssetDetailPage> {
  ItAsset? _asset;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(inventarioApiProvider).buscar(widget.assetTag);
      final exact =
          list.where((a) => a.assetTag == widget.assetTag).firstOrNull;
      setState(() => _asset = exact);
      if (exact == null) setState(() => _error = 'Activo no encontrado');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _agregarImagenes() async {
    if (_asset == null) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería (múltiples)'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = source == ImageSource.gallery
        ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85)
        : [if (await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85) != null) (await picker.pickImage(source: ImageSource.camera))!]
            .whereType<XFile>().toList();
    if (picked.isEmpty) return;

    try {
      await ref.read(inventarioApiProvider).subirImagenes(_asset!.assetTag, picked);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir: $e')),
        );
      }
    }
  }

  Future<void> _eliminarImagen(ItAssetImage img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar imagen'),
        content: const Text('¿Borrar esta foto del activo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(inventarioApiProvider)
          .eliminarImagen(_asset!.assetTag, img.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _cambiarEstado() async {
    if (_asset == null) return;
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Cambiar estado'),
        children: ['Operativo', 'En Revisión', 'Retirado']
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(s),
                  ),
                ))
            .toList(),
      ),
    );
    if (nuevo == null || nuevo == _asset!.status) return;
    try {
      await ref
          .read(inventarioApiProvider)
          .actualizar(_asset!.assetTag, status: nuevo);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _eliminar() async {
    if (_asset == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar activo'),
        content: Text(
            '¿Borrar ${_asset!.assetTag} y todas sus fotos? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).eliminar(_asset!.assetTag);
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Color _statusColor(String? s) => switch (s) {
        'Operativo' => const Color(0xFF10B981),
        'En Revisión' => const Color(0xFFF59E0B),
        'Retirado' => const Color(0xFFEF4444),
        _ => const Color(0xFF6B7280),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(widget.assetTag),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _asset == null ? null : _eliminar,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _galeriaFotos(),
                    const SizedBox(height: 16),
                    _card('Información', [
                      _kv('Tag', _asset!.assetTag),
                      _kv('Categoría', _asset!.category),
                      _kv('Marca', _asset!.brand),
                      _kv('Modelo', _asset!.model),
                      _kv('S/N', _asset!.serialNumber),
                    ]),
                    const SizedBox(height: 12),
                    _card('Ubicación y estado', [
                      _kv('Ubicación', _asset!.location ?? '—'),
                      _kv('Estado', _asset!.status ?? '—',
                          color: _statusColor(_asset!.status)),
                    ]),
                    if (_asset!.notes != null && _asset!.notes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _card('Notas', [
                        Text(_asset!.notes!,
                            style: const TextStyle(fontSize: 13, height: 1.5)),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _cambiarEstado,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Cambiar estado'),
                    ),
                  ],
                ),
    );
  }

  Widget _galeriaFotos() {
    final imgs = _asset!.images;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('FOTOS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF6B7280))),
              ),
              TextButton.icon(
                onPressed: _agregarImagenes,
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (imgs.isEmpty)
            Container(
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Sin fotos',
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: imgs.length,
              itemBuilder: (_, i) {
                final img = imgs[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        img.url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _eliminarImagen(img),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ),
        ],
      ),
    );
  }
}
