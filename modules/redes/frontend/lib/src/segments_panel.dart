import 'package:balgres_it_contacts/balgres_it_contacts.dart' show apiError;
import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';

/// Tarjetas por segmento /24 (calculadas solas). Tocar una filtra la lista; el lápiz le pone nombre.
class SegmentsPanel extends ConsumerWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  final void Function(String cidr) onScan;
  const SegmentsPanel({super.key, required this.selected, required this.onSelect, required this.onScan});

  Future<void> _rename(BuildContext context, WidgetRef ref, Segment s) async {
    final ctrl = TextEditingController(text: s.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nombre de ${s.cidr}'),
        content: SizedBox(
          width: 380,
          child: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Comedor, Colorgres…', helperText: 'Vacío = quitar el nombre')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(redesApiProvider).nombrarSegmento(s.cidr, ctrl.text.trim());
      ref.invalidate(ipsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final segs = ref.watch(segmentsProvider).valueOrNull ?? const <Segment>[];
    if (segs.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Segmentos · toca uno para filtrar'),
      const SizedBox(height: 8),
      SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: segs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final s = segs[i];
            final sel = selected == s.cidr;
            final extra = [
              'En línea ${s.enLinea} · Sin respuesta ${s.sinRespuesta}',
              if (s.borradores > 0) '${s.borradores} reservada(s) por borrador',
            ].join(' · ');
            return SizedBox(
              width: 260,
              child: Container(
                decoration: cardDeco(context, radius: 14).copyWith(border: Border.all(color: sel ? c.accent : c.line, width: sel ? 2 : 1)),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelect(sel ? null : s.cidr),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.name ?? s.cidr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              if (s.name != null) Text(s.cidr, style: TextStyle(fontSize: 11, color: c.muted)),
                            ]),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), iconSize: 18,
                            tooltip: 'Poner nombre', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(context, ref, s),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), iconSize: 18,
                            tooltip: 'Escanear este segmento', icon: const Icon(Icons.radar), onPressed: () => onScan(s.cidr),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: (s.usadas / 254).clamp(0.0, 1.0), minHeight: 6, backgroundColor: c.panel, valueColor: AlwaysStoppedAnimation(c.accent)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${s.usadas} usadas · ${s.libres} libres', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(extra, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.muted)),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
