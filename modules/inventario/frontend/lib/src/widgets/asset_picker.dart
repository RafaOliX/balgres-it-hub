import 'dart:math' as math;

import 'package:balgres_it_ui/asset_link.dart' show keywordsForKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/filters.dart';
import '../data/providers.dart';
import '../models/category.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import 'asset_thumbnail.dart';

/// Selector de activos en modal. Devuelve los tags elegidos (null si se cancela).
/// [kindHint]: tipo de dispositivo (ej. "computadora") para mostrar primero esa categoría.
Future<List<String>?> showAssetPicker(
  BuildContext context, {
  List<String> selected = const [],
  bool multi = true,
  String? kindHint,
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _AssetPickerDialog(selected: selected, multi: multi, kindHint: kindHint),
    );

class _AssetPickerDialog extends ConsumerStatefulWidget {
  final List<String> selected;
  final bool multi;
  final String? kindHint;
  const _AssetPickerDialog({required this.selected, required this.multi, this.kindHint});
  @override
  ConsumerState<_AssetPickerDialog> createState() => _AssetPickerDialogState();
}

class _AssetPickerDialogState extends ConsumerState<_AssetPickerDialog> {
  late List<String> _sel;
  String _q = '';
  Set<int> _cats = {};
  bool _catsTouched = false;

  @override
  void initState() {
    super.initState();
    _sel = [...widget.selected];
  }

  void _toggle(String tag) => setState(() {
        if (_sel.contains(tag)) {
          _sel.remove(tag);
        } else if (widget.multi) {
          _sel.add(tag);
        } else {
          _sel = [tag];
        }
      });

  Set<int> _hinted(List<Category> cats) {
    final kws = keywordsForKind(widget.kindHint);
    if (kws.isEmpty) return {};
    return {for (final c in cats) if (kws.any(normalizeText(c.name).contains)) c.id};
  }

  void _toggleCat(int id, Set<int> active) => setState(() {
        _cats = {...active};
        _catsTouched = true;
        _cats.contains(id) ? _cats.remove(id) : _cats.add(id);
      });

  /// Detalle en un segundo modal: al volver, el selector conserva todo.
  Future<void> _openDetail(ItAsset a) async {
    final r = await showDialog<String>(
      context: context,
      builder: (_) => _AssetDetailDialog(asset: a, selected: _sel.contains(a.assetTag), multi: widget.multi),
    );
    if (r == 'toggle' && mounted) _toggle(a.assetTag);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final size = MediaQuery.sizeOf(context);
    final async = ref.watch(inventarioListProvider);
    final items = (async.valueOrNull ?? const <ItAsset>[]).where((a) => !a.isDraft).toList();
    final cats = ref.watch(categoriasListProvider).valueOrNull ?? const <Category>[];

    final hinted = _hinted(cats);
    final active = _catsTouched ? _cats : hinted;
    final counts = <int, int>{};
    for (final a in items) {
      if (a.categoryId != null) counts[a.categoryId!] = (counts[a.categoryId!] ?? 0) + 1;
    }
    final chipCats = cats.where((x) => (counts[x.id] ?? 0) > 0).toList()..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));

    final terms = normalizeText(_q.trim()).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final shown = items.where((a) {
      if (active.isNotEmpty && !active.contains(a.categoryId)) return false;
      if (terms.isEmpty) return true;
      final hay = normalizeText([a.assetTag, a.category, a.brand, a.model, a.serialNumber, a.location, a.assignedTo, ...a.specs.values].whereType<String>().join(' '));
      return terms.every(hay.contains);
    }).toList()
      ..sort((a, b) => naturalCompare(a.assetTag, b.assetTag));

    final w = math.min(960.0, size.width - 80);
    final h = math.max(320.0, math.min(640.0, size.height - 230));
    final wide = w >= 880;
    final showingHint = !_catsTouched && hinted.isNotEmpty;

    return AlertDialog(
      title: Text(widget.multi ? 'Seleccionar activos' : 'Seleccionar activo'),
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: w,
        height: h,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Buscar por tag, marca, modelo, S/N, IP, ubicación, responsable…', prefixIcon: Icon(Icons.search, size: 20)),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text('Todas · ${items.length}'), selected: active.isEmpty, onSelected: (_) => setState(() { _cats = {}; _catsTouched = true; })),
              ),
              for (final cat in chipCats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(label: Text('${cat.name} · ${counts[cat.id]}'), selected: active.contains(cat.id), onSelected: (_) => _toggleCat(cat.id, active)),
                ),
            ]),
          ),
          if (showingHint)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Sugeridos según el tipo elegido. Toca "Todas" para ver todo el inventario.', style: TextStyle(fontSize: 12, color: c.accent, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          if (wide)
            Container(
              height: 36,
              color: c.panel,
              child: Row(children: [
                const SizedBox(width: 40 + 44 + 12),
                const SizedBox(width: 110, child: SectionLabel('Activo')),
                const Expanded(child: SectionLabel('Equipo')),
                const SizedBox(width: 120, child: SectionLabel('Categoría')),
                const SizedBox(width: 150, child: SectionLabel('Ubicación')),
                const SizedBox(width: 130, child: SectionLabel('Responsable')),
                const SizedBox(width: 120, child: SectionLabel('Estado')),
                const SizedBox(width: 48),
              ]),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: items.isEmpty && async.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? EmptyState(icon: Icons.search_off, title: 'Sin resultados', subtitle: 'Prueba con otra búsqueda o toca "Todas".')
                      : ListView.builder(itemCount: shown.length, itemBuilder: (_, i) => _row(c, shown[i], wide)),
            ),
          ),
        ]),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('${_sel.length} seleccionado${_sel.length == 1 ? '' : 's'}', style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _sel),
          child: Text(widget.multi ? 'Agregar${_sel.isEmpty ? '' : ' (${_sel.length})'}' : 'Elegir'),
        ),
      ],
    );
  }

  Widget _row(SwissColors c, ItAsset a, bool wide) {
    final on = _sel.contains(a.assetTag);
    final icon = widget.multi
        ? (on ? Icons.check_box : Icons.check_box_outline_blank)
        : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    final lead = SizedBox(width: 40, child: Icon(icon, color: on ? c.accent : c.edge));
    final info = IconButton(icon: const Icon(Icons.info_outline, size: 20), tooltip: 'Ver detalle', onPressed: () => _openDetail(a));

    Widget cell(String? s, double width) => SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text((s == null || s.trim().isEmpty) ? '—' : s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: (s == null || s.trim().isEmpty) ? c.muted : c.ink)),
          ),
        );

    final equipo = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('${a.brand} ${a.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      Text('S/N ${a.serialNumber ?? 'N/A'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.muted)),
    ]);

    return InkWell(
      onTap: () => _toggle(a.assetTag),
      child: Container(
        height: 62,
        decoration: BoxDecoration(color: on ? c.accent.withValues(alpha: 0.08) : null, border: Border(bottom: BorderSide(color: c.line))),
        child: wide
            ? Row(children: [
                lead,
                AssetThumbnail(asset: a, size: 44),
                const SizedBox(width: 12),
                cell(a.assetTag, 110),
                Expanded(child: equipo),
                cell(a.category, 120),
                cell(a.location, 150),
                cell(a.assignedTo, 130),
                SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: StatusTag(status: a.status))),
                info,
              ])
            : Row(children: [
                lead,
                AssetThumbnail(asset: a, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(a.assetTag, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('${a.brand} ${a.model} · ${a.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    Text([a.location, a.assignedTo].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.muted)),
                  ]),
                ),
                info,
              ]),
      ),
    );
  }
}

class _AssetDetailDialog extends StatelessWidget {
  final ItAsset asset;
  final bool selected, multi;
  const _AssetDetailDialog({required this.asset, required this.selected, required this.multi});

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final c = context.sw;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(a.assetTag)),
        StatusTag(status: a.status),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a.images.isNotEmpty) ...[
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: a.images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(a.images[i].url, width: 200, height: 150, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 200, color: c.panel)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Kv('Categoría', a.category),
            Kv('Marca', a.brand),
            Kv('Modelo', a.model),
            Kv('S/N', a.serialNumber ?? 'N/A'),
            Kv('Cantidad', '${a.quantity} ${a.unit}'),
            Kv('Ubicación', a.location),
            Kv('Responsable', a.assignedTo),
            if ((a.notes ?? '').isNotEmpty) Kv('Notas', a.notes),
            if (a.specs.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionLabel('Datos técnicos'),
              const SizedBox(height: 4),
              for (final e in a.specs.entries) Kv(e.key, e.value),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'toggle'),
          child: Text(selected ? 'Quitar de la selección' : (multi ? 'Agregar a la selección' : 'Elegir este')),
        ),
      ],
    );
  }
}
