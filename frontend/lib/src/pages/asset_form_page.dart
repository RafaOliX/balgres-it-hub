import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  final _category = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  String _unit = 'Unidad';
  String _status = 'Operativo';

  final List<XFile> _files = [];
  bool _saving = false;
  String? _error;

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    final picked = source == ImageSource.gallery
        ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85)
        : [if (await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85) != null) (await picker.pickImage(source: ImageSource.camera))!].whereType<XFile>().toList();
    if (picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final api = ref.read(inventarioApiProvider);
      final asset = await api.crear(ItAssetCreate(
        assetTag: _tag.text.trim(), category: _category.text.trim(), brand: _brand.text.trim(),
        model: _model.text.trim(), serialNumber: _serial.text.trim(), location: _location.text.trim(),
        status: _status, notes: _notes.text.trim(), quantity: int.tryParse(_quantity.text) ?? 1, unit: _unit,
      ));
      if (_files.isNotEmpty) await api.subirImagenes(asset.assetTag, _files);
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
      appBar: AppBar(title: const Text('Nuevo activo')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            GestureDetector(
              onTap: () => _pickImages(ImageSource.gallery),
              child: Container(
                height: 120, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey),
                  Text('Agregar fotos', style: TextStyle(color: Colors.grey)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(controller: _tag, decoration: const InputDecoration(labelText: 'Asset Tag (Ej. UTP-01)'), validator: (v) => v!.isEmpty ? 'Requerido' : null),
            TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Serial (Opcional para cables)')),
            TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Categoría (Cable UTP, Monitor, etc.)'), validator: (v) => v!.isEmpty ? 'Requerido' : null),
            
            Row(children: [
              Expanded(child: TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                value: _unit,
                decoration: const InputDecoration(labelText: 'Unidad'),
                items: ['Unidad', 'Metro', 'Caja', 'Rollo'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _unit = v!),
              )),
            ]),
            
            Row(children: [
              Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modelo'))),
            ]),
            TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación')),
            DropdownButtonFormField<String>(
              value: _status, decoration: const InputDecoration(labelText: 'Estado'),
              items: ['Operativo', 'En Revisión', 'Retirado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Guardando...' : 'Guardar activo')),
          ],
        ),
      ),
    );
  }
}
