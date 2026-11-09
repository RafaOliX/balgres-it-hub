import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';
import '../widgets/form_fields.dart';

class AssetEditPage extends ConsumerStatefulWidget {
  final ItAsset asset;
  const AssetEditPage({super.key, required this.asset});
  @override
  ConsumerState<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends ConsumerState<AssetEditPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _brand, _model, _serial, _notes, _quantity, _cost, _supplier, _invoice;
  final Map<String, TextEditingController> _specCtrls = {};
  late String _status;
  late int? _locationId;
  bool _locTouched = false;
  DateTime? _purchaseDate, _warrantyUntil;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _brand = TextEditingController(text: a.brand);
    _model = TextEditingController(text: a.model);
    _serial = TextEditingController(text: a.serialNumber);
    _notes = TextEditingController(text: a.notes);
    _quantity = TextEditingController(text: a.quantity.toString());
    _cost = TextEditingController(text: a.cost?.toString() ?? '');
    _supplier = TextEditingController(text: a.supplier);
    _invoice = TextEditingController(text: a.invoiceNumber);
    _status = a.status ?? 'Operativo';
    _locationId = a.locationId;
    _purchaseDate = a.purchaseDate;
    _warrantyUntil = a.warrantyUntil;
    a.specs.forEach((k, v) => _specCtrls[k] = TextEditingController(text: v));
    _loadCategoryFields();
  }

  Future<void> _loadCategoryFields() async {
    try {
      final cats = await ref.read(categoriasListProvider.future);
      final cat = cats.where((c) => c.id == widget.asset.categoryId).firstOrNull;
      if (cat != null && mounted) {
        setState(() {
          for (final f in cat.specFields) {
            _specCtrls.putIfAbsent(f, () => TextEditingController());
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_brand, _model, _serial, _notes, _quantity, _cost, _supplier, _invoice, ..._specCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'serial_number': _serial.text.trim(),
        'status': _status,
        'notes': _notes.text.trim(),
        'quantity': int.tryParse(_quantity.text) ?? 1,
        'purchase_date': dateToApi(_purchaseDate),
        'cost': parseCost(_cost.text),
        'supplier': _supplier.text.trim(),
        'invoice_number': _invoice.text.trim(),
        'warranty_until': dateToApi(_warrantyUntil),
        'specs': collectSpecs(_specCtrls),
      };
      if (_locTouched) body['location_id'] = _locationId;
      await ref.read(inventarioApiProvider).actualizar(widget.asset.assetTag, body);
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text('Editar ${a.assetTag}'), backgroundColor: Colors.white, elevation: 0.5),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              FormSection('Identificación', [
                TextFormField(initialValue: a.assetTag, readOnly: true, decoration: const InputDecoration(labelText: 'Asset Tag (no editable)', border: OutlineInputBorder(), filled: true)),
                const SizedBox(height: 16),
                TextFormField(initialValue: a.category, readOnly: true, decoration: const InputDecoration(labelText: 'Categoría (no editable)', border: OutlineInputBorder(), filled: true)),
                const SizedBox(height: 16),
                TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'S/N', border: OutlineInputBorder())),
              ]),
              FormSection('Detalles del equipo', [
                Row(children: [
                  Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()), child: Text(a.unit))),
                ]),
              ]),
              FormSection('Datos técnicos', [SpecsFields(ctrls: _specCtrls)]),
              FormSection('Compra y garantía', [
                PurchaseFields(
                  purchaseDate: _purchaseDate, warrantyUntil: _warrantyUntil,
                  onPurchase: (d) => setState(() => _purchaseDate = d), onWarranty: (d) => setState(() => _warrantyUntil = d),
                  cost: _cost, supplier: _supplier, invoice: _invoice,
                ),
              ]),
              FormSection('Ubicación y estado', [
                if (a.locationId == null && a.location != null)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Ubicación actual (texto libre): ${a.location}. Elige una del catálogo o usa "Unificar desde activos" en Catálogos.', style: const TextStyle(color: Colors.orange, fontSize: 12))),
                LocationDropdown(value: _locationId, onChanged: (v) => setState(() { _locationId = v; _locTouched = true; })),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status, decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                  items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()), maxLines: 3),
                const SizedBox(height: 8),
                const Text('Para cambiar el responsable usa la pestaña Asignaciones del detalle.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Guardar cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ),
    );
  }
}
