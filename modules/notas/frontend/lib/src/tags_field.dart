import 'package:balgres_it_ui/balgres_it_ui.dart';
import 'package:flutter/material.dart';

/// Etiquetas como chips. Al escribir (o al enfocar) sugiere las ya usadas en otras notas, con su conteo.
/// Coma o Enter agregan; si coincide con una existente (sin importar mayúsculas) usa la grafía original.
class TagsField extends StatefulWidget {
  final List<String> tags;
  final Map<String, int> known; // etiqueta -> nº de notas, ya ordenado por uso
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  const TagsField({super.key, required this.tags, required this.known, required this.onChanged, this.enabled = true});

  @override
  State<TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<TagsField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final t = raw.replaceAll(',', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isNotEmpty) {
      final canon = widget.known.keys.where((k) => k.toLowerCase() == t.toLowerCase()).firstOrNull ?? t;
      if (!widget.tags.any((x) => x.toLowerCase() == canon.toLowerCase()) && widget.tags.length < 20) {
        widget.onChanged([...widget.tags, canon]);
      }
    }
    _ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.clear());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in widget.tags)
              InputChip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: widget.enabled ? () => widget.onChanged([...widget.tags]..remove(t)) : null,
              ),
          ]),
        ),
      if (widget.enabled)
        LayoutBuilder(
          builder: (context, cs) => RawAutocomplete<String>(
            textEditingController: _ctrl,
            focusNode: _focus,
            optionsBuilder: (tv) {
              final q = normalizeText(tv.text.trim());
              final used = widget.tags.map((e) => e.toLowerCase()).toSet();
              final pool = widget.known.keys.where((s) => !used.contains(s.toLowerCase()));
              return (q.isEmpty ? pool : pool.where((s) => normalizeText(s).contains(q))).take(8);
            },
            onSelected: _add,
            fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
              controller: ctrl,
              focusNode: focus,
              onChanged: (v) {
                if (v.endsWith(',')) _add(v);
              },
              onSubmitted: (v) {
                _add(v);
                focus.requestFocus();
              },
              decoration: const InputDecoration(
                hintText: 'Agregar etiqueta (Enter o coma)…',
                prefixIcon: Icon(Icons.sell_outlined, size: 18),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: c.bg,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 280, maxWidth: cs.maxWidth),
                  child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), shrinkWrap: true, children: [
                    for (final o in options)
                      InkWell(
                        onTap: () => onSelected(o),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          child: Row(children: [
                            Expanded(child: Text(o, style: const TextStyle(fontSize: 14))),
                            Text('${widget.known[o] ?? 0} nota${(widget.known[o] ?? 0) == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: c.muted)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
