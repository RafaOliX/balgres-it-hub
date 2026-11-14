import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventario_api.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import '../widgets/form_fields.dart';
import '../widgets/search_select.dart';

class AssetEditPage extends ConsumerStatefulWidget {
  final ItAsset asset;
  const AssetEditPage({super.key, required this.asset});
  @override
  ConsumerState<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends ConsumerState<AssetEditPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _brand, _model, _serial, _notes, _quantity;
  final Map<String, TextEditingController> _specCtrls = {};
  late String _status;
  late int? _locationId;
  bool _locTouched = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  TextEditingController _ctrl(String? text) => TextEditingController(text: text ?? '')..addListener(_touch);

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _brand = _ctrl(a.brand);
    _model = _ctrl(a.model);
    _serial = _ctrl(a.serialNumber);
    _notes = _ctrl(a.notes);
    _quantity = _ctrl(a.quantity.toString());
    _status = a.status ?? 'Operativo';
    _locationId = a.locationId;
    a.specs.forEach((k, v) => _specCtrls[k] = _ctrl(v));
    _loadCategoryFields();
  }

  Future<void> _loadCategoryFields() async {
    try {
      final cats = await ref.read(categoriasListProvider.future);
      final cat = cats.where((c) => c.id == widget.asset.categoryId).firstOrNull;
      if (cat != null && mounted) {
        setState(() {
          for (final f in cat.specFields) {
            _specCtrls.putIfAbsent(f, () => _ctrl(null));
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_brand, _model, _serial, _notes, _quantity, ..._specCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Devuelve true si guardó.
  Future<bool> _submit() async {
    if (!_form.currentState!.validate()) return false;
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
        'specs': collectSpecs(_specCtrls),
      };
      if (_locTouched) body['location_id'] = _locationId;
      await ref.read(inventarioApiProvider).actualizar(widget.asset.assetTag, body);
      ref.invalidate(inventarioListProvider);
      _dirty = false;
      if (mounted) Navigator.of(context).pop();
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onBackBlocked() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.edit_note, color: context.sw.accent, size: 36),
        title: const Text('Tienes cambios sin guardar'),
        content: Text('Hiciste cambios en ${widget.asset.assetTag} que aún no se guardan. ¿Qué quieres hacer?'),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(style: TextButton.styleFrom(foregroundColor: context.sw.bad), onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Salir sin guardar')),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Seguir editando')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar')),
          ]),
        ],
      ),
    );
    if (r == 'discard') {
      _dirty = false;
      if (mounted) Navigator.of(context).pop();
    } else if (r == 'save') {
      await _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final c = context.sw;
    final hints = ref.watch(hintsProvider);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackBlocked();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Editar ${a.assetTag}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line)), boxShadow: softShadow(context)),
          child: SafeArea(
            top: false,
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Row(children: [
                  if (_dirty) ...[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: c.warn, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('Cambios sin guardar', style: TextStyle(color: c.muted, fontSize: 13)),
                  ],
                  const Spacer(),
                  OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).maybePop(), child: const Text('Cancelar')),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                  ),
                ]),
              ),
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(24), children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.bad.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.bad)),
                    child: Text(_error!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)),
                  ),
                FormSection('Identificación', [
                  TextFormField(initialValue: a.assetTag, readOnly: true, decoration: const InputDecoration(labelText: 'Asset Tag (no editable)')),
                  const SizedBox(height: 16),
                  TextFormField(initialValue: a.category, readOnly: true, decoration: const InputDecoration(labelText: 'Categoría (no editable)')),
                  const SizedBox(height: 16),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'S/N')),
                ]),
                FormSection('Detalles del equipo', [
                  Row(children: [
                    Expanded(child: SuggestField(controller: _brand, label: 'Marca', suggestions: () => hints.brands)),
                    const SizedBox(width: 16),
                    Expanded(child: SuggestField(controller: _model, label: 'Modelo', suggestions: () => hints.modelsFor(_brand.text))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
                    const SizedBox(width: 16),
                    Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad'), child: Text(a.unit))),
                  ]),
                ]),
                FormSection('Datos técnicos', [SpecsFields(ctrls: _specCtrls, hints: hints.specs, assetTag: a.assetTag)]),
                FormSection('Ubicación y estado', [
                  if (a.locationId == null && a.location != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Ubicación actual (texto libre): ${a.location}. Elige una del catálogo o usa "Unificar desde activos" en Catálogos.', style: TextStyle(color: c.warn, fontSize: 12)),
                    ),
                  LocationDropdown(value: _locationId, onChanged: (v) => setState(() { _locationId = v; _locTouched = true; _dirty = true; })),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() { _status = v!; _dirty = true; }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 3),
                  const SizedBox(height: 8),
                  Text('Para cambiar el responsable usa la pestaña Asignaciones del detalle.', style: TextStyle(color: c.muted, fontSize: 12)),
                ]),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
