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

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const DateField({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context, initialDate: value ?? now,
            firstDate: DateTime(2000), lastDate: DateTime(now.year + 15),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today, size: 18)
                : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => onChanged(null)),
          ),
          child: Text(value == null ? '—' : value!.toIso8601String().substring(0, 10)),
        ),
      );
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

class PurchaseFields extends StatelessWidget {
  final DateTime? purchaseDate;
  final DateTime? warrantyUntil;
  final ValueChanged<DateTime?> onPurchase;
  final ValueChanged<DateTime?> onWarranty;
  final TextEditingController cost;
  final TextEditingController supplier;
  final TextEditingController invoice;
  final List<String> supplierHints;
  const PurchaseFields({
    super.key, required this.purchaseDate, required this.warrantyUntil, required this.onPurchase,
    required this.onWarranty, required this.cost, required this.supplier, required this.invoice,
    this.supplierHints = const [],
  });

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(child: DateField(label: 'Fecha de compra', value: purchaseDate, onChanged: onPurchase)),
          const SizedBox(width: 16),
          Expanded(child: DateField(label: 'Garantía hasta', value: warrantyUntil, onChanged: onWarranty)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextFormField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo', prefixText: '\$ '))),
          const SizedBox(width: 16),
          Expanded(child: SuggestField(controller: supplier, label: 'Proveedor', suggestions: () => supplierHints)),
        ]),
        const SizedBox(height: 16),
        TextFormField(controller: invoice, decoration: const InputDecoration(labelText: 'N° de factura')),
      ]);
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

double? parseCost(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
