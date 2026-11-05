import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';

class AssetFormPage extends ConsumerStatefulWidget {
  const AssetFormPage({super.key});

  @override
  ConsumerState<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends ConsumerState<AssetFormPage> {
  final _form = GlobalKey<FormState>();
  final _tag = TextEditingController();
  final _category = TextEditingController(text: 'Monitor');
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _location = TextEditingController();
  String _status = 'Operativo';
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventarioApiProvider).crear(ItAssetCreate(
            assetTag: _tag.text.trim(),
            category: _category.text.trim(),
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            serialNumber: _serial.text.trim(),
            location: _location.text.trim(),
            status: _status,
            notes: _notes.text.trim(),
          ));
      ref.invalidate(inventarioListProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Nuevo activo'),
        elevation: 0,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            TextFormField(
              controller: _tag,
              decoration:
                  const InputDecoration(labelText: 'Asset Tag *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _category,
              decoration:
                  const InputDecoration(labelText: 'Categoría *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Marca'),
            ),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Modelo'),
            ),
            TextFormField(
              controller: _serial,
              decoration: const InputDecoration(
                  labelText: 'Número de serie *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Ubicación'),
            ),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(
                    value: 'Operativo', child: Text('Operativo')),
                DropdownMenuItem(
                    value: 'En Revisión', child: Text('En Revisión')),
                DropdownMenuItem(
                    value: 'Retirado', child: Text('Retirado')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'Operativo'),
            ),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Guardando…' : 'Guardar activo'),
            ),
          ],
        ),
      ),
    );
  }
}
