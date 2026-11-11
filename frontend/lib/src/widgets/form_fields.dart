import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/catalogs.dart';
import '../ui/swiss.dart';
import 'search_select.dart';

class FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const FormSection(this.title, this.children, {super.key});

  @override
  Widget build(BuildContext context) => SwissSection(title, children);
}

/// Ubicación con búsqueda: escribe "rack" y trae "Informática › Sala › Rack 1".
class LocationDropdown extends ConsumerWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;
  const LocationDropdown({super.key, required this.value, required this.onChanged, this.label = 'Ubicación'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ubicacionesProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (locs) => SearchSelect<Location>(
        label: label,
        value: locs.where((l) => l.id == value).firstOrNull,
        options: locs,
        display: (l) => l.fullName,
        subtitle: (l) => l.kind ?? '',
        hint: 'Escribe para buscar: Informática, rack…',
        onChanged: (l) => onChanged(l?.id),
      ),
    );
  }
}

class SpecsFields extends StatelessWidget {
  final Map<String, TextEditingController> ctrls;
  final Map<String, List<String>> hints;
  const SpecsFields({super.key, required this.ctrls, this.hints = const {}});

  @override
  Widget build(BuildContext context) {
    if (ctrls.isEmpty) {
      return Text('Esta categoría no tiene campos técnicos. Puedes definirlos en Categorías.', style: TextStyle(color: context.sw.muted, fontSize: 13));
    }
    return Wrap(
      spacing: 16, runSpacing: 16,
      children: ctrls.entries
          .map((e) => SizedBox(width: 240, child: SuggestField(controller: e.value, label: e.key, suggestions: () => hints[e.key] ?? const [])))
          .toList(),
    );
  }
}

Map<String, String> collectSpecs(Map<String, TextEditingController> ctrls) {
  final m = <String, String>{};
  ctrls.forEach((k, c) {
    final t = c.text.trim();
    if (t.isNotEmpty) m[k] = t;
  });
  return m;
}
