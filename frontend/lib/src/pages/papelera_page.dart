import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';

class PapeleraPage extends ConsumerStatefulWidget {
  const PapeleraPage({super.key});
  @override
  ConsumerState<PapeleraPage> createState() => _PapeleraPageState();
}

class _PapeleraPageState extends ConsumerState<PapeleraPage> {
  List<ItAsset> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(inventarioApiProvider).getPapelera();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      _snack(apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restaurar(ItAsset a) async {
    try {
      await ref.read(inventarioApiProvider).restaurar(a.assetTag);
      ref.invalidate(inventarioListProvider);
      _load();
    } catch (e) {
      _snack(apiError(e));
    }
  }

  Future<void> _purgar(ItAsset a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar definitivamente'),
        content: Text('Se borrará ${a.assetTag} con su historial y fotos. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inventarioApiProvider).purgar(a.assetTag);
      _load();
    } catch (e) {
      _snack(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(title: const Text('Papelera'), backgroundColor: Colors.white, elevation: 0.5),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(child: Text('La papelera está vacía'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = _items[i];
                      return ListTile(
                        tileColor: Colors.white,
                        leading: const Icon(Icons.delete_outline),
                        title: Text('${a.assetTag} · ${a.brand} ${a.model}'),
                        subtitle: Text('${a.category} · eliminado ${a.deletedAt?.toString().substring(0, 16) ?? ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton.icon(onPressed: () => _restaurar(a), icon: const Icon(Icons.restore), label: const Text('Restaurar')),
                          IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), tooltip: 'Eliminar definitivamente', onPressed: () => _purgar(a)),
                        ]),
                      );
                    },
                  ),
      );
}
