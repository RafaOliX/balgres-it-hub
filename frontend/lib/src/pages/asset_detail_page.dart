import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> _generarPdf() async {
    final url = Uri.parse('http://192.0.0.69:8091/api/inventario/${widget.assetTag}/pdf');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
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
            IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _asset != null ? _generarPdf : null, tooltip: 'Generar PDF'),
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
            ListView(padding: const EdgeInsets.all(16), children: [
              if (_asset!.imageUrl != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_asset!.imageUrl!, height: 200, fit: BoxFit.cover)),
              const SizedBox(height: 16),
              _card('Información', [
                _kv('Tag', _asset!.assetTag),
                _kv('Cantidad', '${_asset!.quantity} ${_asset!.unit}'),
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
            _history.isEmpty ? const Center(child: Text('Sin cambios registrados')) : ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: _history.length, separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: Text('Cambió: ${_history[i].fieldName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('De: ${_history[i].oldValue ?? "vacío"} a: ${_history[i].newValue ?? "vacío"}'),
                trailing: Text(_history[i].changedAt.toString().substring(0, 16), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)), const SizedBox(height: 10), ...children]),
  );

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 80, child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey))), Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))]));
}
