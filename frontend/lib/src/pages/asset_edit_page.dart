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
  late TextEditingController _tag, _category, _brand, _model, _serial, _location, _notes;
  late String _status;
  bool _saving = false;

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
    _status = widget.asset.status ?? 'Operativo';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventarioApiProvider).actualizar(
        widget.asset.assetTag,
        assetTag: _tag.text.trim(), category: _category.text.trim(),
        brand: _brand.text.trim(), model: _model.text.trim(),
        serialNumber: _serial.text.trim(), location: _location.text.trim(),
        status: _status, notes: _notes.text.trim(),
      );
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar activo')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _tag, decoration: const InputDecoration(labelText: 'Asset Tag *'), validator: (v) => v!.isEmpty ? 'Requerido' : null),
            TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'S/N *'), validator: (v) => v!.isEmpty ? 'Requerido' : null),
            TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Categoría *'), validator: (v) => v!.isEmpty ? 'Requerido' : null),
            Row(children: [
              Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo'))),
            ]),
            TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación')),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'Operativo', child: Text('Operativo')),
                DropdownMenuItem(value: 'En Revisión', child: Text('En Revisión')),
                DropdownMenuItem(value: 'Retirado', child: Text('Retirado')),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 3),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
            )
          ],
        ),
      ),
    );
  }
}
