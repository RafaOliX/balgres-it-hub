import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../data/table_prefs.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';

Future<T?> _pickOne<T>(BuildContext context, String title, String label, List<(T, String)> opts, String confirm) {
  T? sel;
  return showDialog<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setM) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: DropdownButtonFormField<T>(
            value: sel,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [for (final o in opts) DropdownMenuItem<T>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setM(() => sel = v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: sel == null ? null : () => Navigator.pop(ctx, sel), child: Text(confirm)),
        ],
      ),
    ),
  );
}

class BulkBar extends ConsumerWidget {
  final List<ItAsset> selected;
  const BulkBar({super.key, required this.selected});

  Future<void> _run(BuildContext context, WidgetRef ref, String okMsg, Future<void> Function(ItAsset) op) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = 0, fail = 0;
    String? lastErr;
    for (final a in selected) {
      try {
        await op(a);
        ok++;
      } catch (e) {
        fail++;
        lastErr = apiError(e);
      }
    }
    ref.invalidate(inventarioListProvider);
    ref.read(selectionProvider.notifier).state = <String>{};
    messenger.showSnackBar(SnackBar(content: Text('$okMsg: $ok correctos${fail > 0 ? ' · $fail con error ($lastErr)' : ''}')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final api = ref.read(inventarioApiProvider);
    final on = ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark ? Colors.white : Colors.black;

    Widget btn(IconData icon, String label, VoidCallback onTap) => TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: TextButton.styleFrom(foregroundColor: on),
        );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text('${selected.length} seleccionado${selected.length == 1 ? '' : 's'}', style: TextStyle(color: on, fontWeight: FontWeight.w800)),
          const SizedBox(width: 16),
          btn(Icons.qr_code_2, 'Etiquetas QR', () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await api.descargarEtiquetas(selected.map((a) => a.assetTag).toList());
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('Error: ${apiError(e)}')));
            }
          }),
          btn(Icons.flag_outlined, 'Estado', () async {
            final s = await _pickOne<String>(context, 'Cambiar estado', 'Nuevo estado',
                [for (final s in const ['Operativo', 'En Revisión', 'Retirado']) (s, s)], 'Aplicar');
            if (s != null && context.mounted) await _run(context, ref, 'Estado actualizado', (a) => api.actualizar(a.assetTag, {'status': s}));
          }),
          btn(Icons.place_outlined, 'Ubicación', () async {
            final locs = await ref.read(ubicacionesProvider.future);
            if (!context.mounted) return;
            final id = await _pickOne<int>(context, 'Mover a ubicación', 'Ubicación', [for (final l in locs) (l.id, l.fullName)], 'Mover');
            if (id != null && context.mounted) await _run(context, ref, 'Movidos', (a) => api.actualizar(a.assetTag, {'location_id': id}));
          }),
          btn(Icons.person_add_alt, 'Asignar', () async {
            final emps = (await ref.read(empleadosProvider.future)).where((e) => e.active).toList();
            if (!context.mounted) return;
            final id = await _pickOne<int>(context, 'Asignar a empleado', 'Empleado', [for (final e in emps) (e.id, e.name)], 'Asignar');
            if (id != null && context.mounted) await _run(context, ref, 'Asignados', (a) => api.asignar(a.assetTag, id, ''));
          }),
          btn(Icons.delete_outline, 'Papelera', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Enviar a la papelera'),
                content: Text('Se enviarán ${selected.length} activos a la papelera. Podrás restaurarlos.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
                ],
              ),
            );
            if (ok == true && context.mounted) await _run(context, ref, 'Enviados a la papelera', (a) => api.eliminar(a.assetTag));
          }),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Quitar selección',
            icon: Icon(Icons.close, color: on),
            onPressed: () => ref.read(selectionProvider.notifier).state = <String>{},
          ),
        ]),
      ),
    );
  }
}
