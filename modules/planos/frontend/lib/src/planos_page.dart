import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'providers.dart';

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
    await context.push('/planos/${p.id}');
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

