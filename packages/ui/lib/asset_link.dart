import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'swiss.dart';
import 'text.dart';

/// Datos mínimos de un activo para mostrarlo fuera de inventario (chips de notas, pines de planos).
class AssetRef {
  final String tag, title, category;
  final String? imageUrl, status, location;
  const AssetRef({required this.tag, required this.title, required this.category, this.imageUrl, this.status, this.location});
}

typedef AssetPicker = Future<List<String>?> Function(BuildContext context, {List<String> selected, bool multi, String? kindHint});

/// El shell lo reemplaza con el selector de inventario. Si es null, los módulos ocultan el botón.
final assetPickerProvider = Provider<AssetPicker?>((ref) => null);

/// {tag: AssetRef}. El shell lo llena desde inventario.
final assetRefsProvider = Provider<Map<String, AssetRef>>((ref) => const {});

/// Tipo de pin / dispositivo -> palabras que aparecen en el nombre de la categoría de inventario.
const kKindKeywords = <String, List<String>>{
  'camara': ['camara', 'cctv'],
  'nvr': ['nvr', 'dvr', 'grabador'],
  'switch': ['switch'],
  'ap': ['access point', 'punto de acceso', 'wifi', 'inalambr'],
  'rack': ['rack'],
  'router': ['router'],
  'computadora': ['comput', 'laptop', 'portatil', 'notebook'],
  'impresora': ['impres', 'printer'],
  'monitor': ['monitor', 'pantalla'],
  'telefono': ['telefon'],
  'servidor': ['servidor', 'server'],
  'ups': ['ups', 'bateria'],
};

List<String> keywordsForKind(String? kind) => kind == null ? const [] : (kKindKeywords[kind] ?? const []);

/// Deduce el tipo de dispositivo a partir de la categoría del activo (null si no coincide).
String? kindForCategory(String category) {
  final n = normalizeText(category);
  for (final e in kKindKeywords.entries) {
    if (e.value.any(n.contains)) return e.key;
  }
  return null;
}

/// Activos vinculados como chips (foto + tag + equipo) y botón que abre el selector de inventario.
class AssetLinksField extends ConsumerWidget {
  final String label;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final void Function(String tag)? onOpen;
  final bool enabled, multi;
  final String? kindHint;

  const AssetLinksField({
    super.key, required this.label, required this.tags, required this.onChanged,
    this.onOpen, this.enabled = true, this.multi = true, this.kindHint,
  });

  Widget _chip(BuildContext context, SwissColors c, String tag, AssetRef? r, bool unknown) {
    final col = unknown ? c.warn : c.line;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Container(
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: col)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpen == null ? null : () => onOpen!(tag),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 34, height: 34,
                    child: r?.imageUrl != null
                        ? Image.network(r!.imageUrl!, fit: BoxFit.cover, cacheWidth: 102, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, size: 18, color: c.muted))
                        : Icon(Icons.inventory_2_outlined, size: 18, color: c.muted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(unknown ? 'No está en inventario' : (r?.title ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: unknown ? c.warn : c.muted)),
                  ]),
                ),
                if (enabled)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged([...tags]..remove(tag)),
                    child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close, size: 16, color: c.muted)),
                  )
                else
                  const SizedBox(width: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sw;
    final refs = ref.watch(assetRefsProvider);
    final picker = ref.watch(assetPickerProvider);

    Future<void> pick() async {
      final r = await picker!(context, selected: tags, multi: multi, kindHint: kindHint);
      if (r != null) onChanged(r);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel(label),
      const SizedBox(height: 8),
      if (tags.isEmpty) Text(multi ? 'Ningún activo vinculado.' : 'Sin activo vinculado.', style: TextStyle(fontSize: 13, color: c.muted)),
      if (tags.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in tags) _chip(context, c, t, refs[t], refs.isNotEmpty && !refs.containsKey(t)),
        ]),
      if (enabled && picker != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.add_link, size: 18),
            label: Text(tags.isEmpty ? (multi ? 'Agregar activos' : 'Elegir activo') : (multi ? 'Editar selección' : 'Cambiar activo')),
          ),
        ),
    ]);
  }
}
