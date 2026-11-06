import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/providers.dart';
import '../models/it_asset.dart';

class AssetEditPage extends ConsumerStatefulWidget {
  final ItAsset asset;
  const AssetEditPage({super.key, required this.asset});
  @override
  ConsumerState<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends ConsumerState<AssetEditPage> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _tag, _category, _brand, _model, _serial, _location, _notes, _quantity, _assignedTo;
  late String _status;
  late String _unit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tag = TextEditingController(text: widget.asset.assetTag);
    _category = TextEditingController(text: widget.asset.category);
    _brand = TextEditingController(text: widget.asset.brand);
    _model = TextEditingController(text: widget.asset.model);
    _serial = TextEditingController(text: widget.asset.serialNumber);
    _location = TextEditingController(text: widget.asset.location);
    _notes = TextEditingController(text: widget.asset.notes);
    _quantity = TextEditingController(text: widget.asset.quantity.toString());
    _assignedTo = TextEditingController(text: widget.asset.assignedTo);
    _status = widget.asset.status ?? 'Operativo';
    _unit = widget.asset.unit;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(inventarioApiProvider).actualizar(widget.asset.assetTag, {
        'asset_tag': _tag.text.trim(),
        'category': _category.text.trim(),
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'serial_number': _serial.text.trim(),
        'location': _location.text.trim(),
        'status': _status,
        'notes': _notes.text.trim(),
        'quantity': int.tryParse(_quantity.text) ?? 1,
        'unit': _unit,
        'assigned_to': _assignedTo.text.trim(),
      });
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280), letterSpacing: 0.8)),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('Editar activo'), backgroundColor: Colors.white, elevation: 0.5),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_error != null) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16), 
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                
                _section('Identificación', [
                  TextFormField(controller: _tag, decoration: const InputDecoration(labelText: 'Asset Tag *', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Requerido' : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Categoría *', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Requerido' : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'S/N (Opcional)', border: OutlineInputBorder())),
                ]),

                _section('Detalles del Equipo', [
                  Row(children: [
                    Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()))),
                    const SizedBox(width: 16),
                    Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()))),
                    const SizedBox(width: 16),
                    Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()), child: Text(_unit))),
                  ]),
                ]),

                _section('Asignación y Ubicación', [
                  TextFormField(controller: _assignedTo, decoration: const InputDecoration(labelText: 'Asignado a (Responsable)', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación Física', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _status, decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
                    items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()), maxLines: 3),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
