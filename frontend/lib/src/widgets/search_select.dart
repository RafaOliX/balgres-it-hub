import 'package:flutter/material.dart';

import '../data/filters.dart';
import '../ui/swiss.dart';

Widget _optionsPanel<T extends Object>({
  required BuildContext context,
  required double width,
  required AutocompleteOnSelected<T> onSelected,
  required Iterable<T> options,
  required Widget Function(T option, bool highlighted) tile,
}) {
  final c = context.sw;
  final list = options.toList();
  final hi = AutocompleteHighlightedOption.of(context);
  return Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 8,
      color: c.bg,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 280, maxWidth: width),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          itemCount: list.length,
          itemBuilder: (_, i) => InkWell(onTap: () => onSelected(list[i]), child: tile(list[i], i == hi)),
        ),
      ),
    ),
  );
}

/// Lista desplegable en la que también se puede ESCRIBIR para filtrar (sin tildes, varias palabras).
class SearchSelect<T extends Object> extends StatefulWidget {
  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) display;
  final String Function(T)? subtitle;
  final String Function(T)? searchText;
  final ValueChanged<T?> onChanged;
  final bool required;
  final bool allowClear;
  final String? hint;

  const SearchSelect({
    super.key, required this.label, required this.value, required this.options, required this.display,
    required this.onChanged, this.subtitle, this.searchText, this.required = false, this.allowClear = true, this.hint,
  });

  @override
  State<SearchSelect<T>> createState() => _SearchSelectState<T>();
}

class _SearchSelectState<T extends Object> extends State<SearchSelect<T>> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  String _text(T? v) => v == null ? '' : widget.display(v);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _text(widget.value));
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant SearchSelect<T> old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctrl.text != _text(widget.value)) _ctrl.text = _text(widget.value);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length); // escribir reemplaza
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_ctrl.text.trim().isEmpty && widget.allowClear && !widget.required) {
        if (widget.value != null) widget.onChanged(null);
      } else if (_ctrl.text != _text(widget.value)) {
        _ctrl.text = _text(widget.value);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return LayoutBuilder(
      builder: (context, cs) => RawAutocomplete<T>(
        textEditingController: _ctrl,
        focusNode: _focus,
        displayStringForOption: widget.display,
        optionsBuilder: (tv) {
          final raw = tv.text.trim();
          final showAll = raw.isEmpty || (widget.value != null && tv.text == _text(widget.value));
          if (showAll) return widget.options.take(80);
          final terms = normalizeText(raw).split(RegExp(r'\s+'));
          return widget.options.where((o) {
            final hay = normalizeText('${widget.display(o)} ${widget.searchText?.call(o) ?? ''}');
            return terms.every(hay.contains);
          }).take(80);
        },
        onSelected: (o) => widget.onChanged(o),
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
          controller: ctrl,
          focusNode: focus,
          decoration: InputDecoration(
            labelText: widget.label + (widget.required ? ' *' : ''),
            hintText: widget.hint ?? 'Escribe para buscar…',
            suffixIcon: (widget.value != null && widget.allowClear && !widget.required)
                ? IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Quitar', onPressed: () { ctrl.clear(); widget.onChanged(null); })
                : Icon(Icons.unfold_more, size: 18, color: c.muted),
          ),
          validator: (_) => widget.required && widget.value == null ? 'Requerido' : null,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, onSelected, options) => _optionsPanel<T>(
          context: context,
          width: cs.maxWidth,
          onSelected: onSelected,
          options: options,
          tile: (o, hi) {
            final sub = widget.subtitle?.call(o) ?? '';
            return Container(
              color: hi ? c.accent.withValues(alpha: 0.10) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.display(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Campo de texto libre que sugiere valores ya usados (marca, modelo, proveedor…).
class SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<String> Function() suggestions;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onPicked;

  const SuggestField({
    super.key, required this.controller, required this.label, required this.suggestions,
    this.validator, this.keyboardType, this.onPicked,
  });

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return LayoutBuilder(
      builder: (context, cs) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (tv) {
          final all = widget.suggestions();
          final raw = tv.text.trim();
          if (raw.isEmpty) return all.take(10);
          final q = normalizeText(raw);
          final starts = <String>[], has = <String>[];
          for (final s in all) {
            if (s == raw) continue;
            final n = normalizeText(s);
            if (n.startsWith(q)) {
              starts.add(s);
            } else if (n.contains(q)) {
              has.add(s);
            }
          }
          return [...starts, ...has].take(8);
        },
        onSelected: (s) => widget.onPicked?.call(s),
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(labelText: widget.label),
          validator: widget.validator,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, onSelected, options) => _optionsPanel<String>(
          context: context,
          width: cs.maxWidth,
          onSelected: onSelected,
          options: options,
          tile: (o, hi) => Container(
            color: hi ? c.accent.withValues(alpha: 0.10) : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
